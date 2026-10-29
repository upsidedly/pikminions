// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Foundation
import Antille
import CSQLite

enum PikminKeychain {
    static func read(_ account:String)->String? {
        LocalCredentialStore.read(service:"dev.upsided.pikminions",account:account)
    }
    static func save(_ value:String,account:String) throws {
        try LocalCredentialStore.save(value,service:"dev.upsided.pikminions",account:account)
    }
    static func delete(_ account:String) {
        LocalCredentialStore.delete(service:"dev.upsided.pikminions",account:account)
    }
}
struct SQLiteMetadata {
    static func rows(path:String,sql:String) throws -> [[String:String]] {
        var db:OpaquePointer?
        guard sqlite3_open_v2(path,&db,SQLITE_OPEN_READONLY|SQLITE_OPEN_NOMUTEX,nil)==SQLITE_OK,let db else {
            if let db {sqlite3_close(db)};throw SourceFailure.message("Recorded metadata is unavailable.")
        }
        defer {sqlite3_close(db)}
        sqlite3_busy_timeout(db,150)
        sqlite3_exec(db,"PRAGMA query_only=ON",nil,nil,nil)
        var statement:OpaquePointer?
        guard sqlite3_prepare_v2(db,sql,-1,&statement,nil)==SQLITE_OK,let statement else {
            throw SourceFailure.message("This metadata version is not supported.")
        }
        defer {sqlite3_finalize(statement)}
        var result:[[String:String]]=[]
        var status=sqlite3_step(statement)
        while status==SQLITE_ROW {
            var row:[String:String]=[:]
            for i in 0..<sqlite3_column_count(statement) {
                guard let name=sqlite3_column_name(statement,i),let text=sqlite3_column_text(statement,i) else {continue}
                row[String(cString:name)]=String(cString:text)
            }
            result.append(row)
            status=sqlite3_step(statement)
        }
        guard status==SQLITE_DONE else {throw SourceFailure.message("Recorded metadata could not be read completely.")}
        return result
    }
    static func codexAliases() -> [String:String] {
        let path=FileManager.default.homeDirectoryForCurrentUser.appending(path:".t3/userdata/statev2.sqlite").path
        let sql="SELECT provider_thread_id,json_extract(payload_json,'$.nativeThreadRef.nativeId') AS native_id FROM orchestration_v2_projection_provider_threads WHERE driver='codex' AND json_extract(payload_json,'$.nativeThreadRef.strength')='strong'"
        let rows=(try? rows(path:path,sql:sql)) ?? []
        return Dictionary(rows.compactMap { row -> (String,String)? in
            guard let id=row["provider_thread_id"],let native=row["native_id"],!native.isEmpty else {return nil}
            return(id,native)
        },uniquingKeysWith:{$1})
    }
    static func recordedCodex() throws -> [AgentRecord] {
        let home=FileManager.default.homeDirectoryForCurrentUser.appending(path:".codex")
        let threads=try rows(path:home.appending(path:"state_5.sqlite").path,sql:"SELECT id,title,name,cwd,COALESCE(updated_at_ms,updated_at*1000) AS updated FROM threads WHERE archived=0 ORDER BY updated DESC LIMIT 60")
        let history=(try? rows(path:home.appending(path:"thread_history_1.sqlite").path,sql:"SELECT thread_id,turn_id,status,completed_at FROM thread_turns t WHERE rollout_ordinal=(SELECT MAX(rollout_ordinal) FROM thread_turns x WHERE x.thread_id=t.thread_id)")) ?? []
        let byID=Dictionary(history.compactMap {row -> (String,[String:String])? in row["thread_id"].map{($0,row)}},uniquingKeysWith:{$1})
        let edges=(try? rows(path:home.appending(path:"state_5.sqlite").path,sql:"SELECT parent_thread_id,child_thread_id FROM thread_spawn_edges")) ?? []
        let parents=Dictionary(edges.compactMap{row -> (String,String)? in guard let c=row["child_thread_id"],let p=row["parent_thread_id"] else{return nil};return(c,p)},uniquingKeysWith:{$1})
        return threads.compactMap { row in
            guard let id=row["id"] else{return nil}
            let turn=byID[id]
            return AgentRecord(id:"codex:"+id,nativeID:id,source:"Codex",threadID:id,runID:turn?["turn_id"] ?? "",
                title:row["name"].flatMap{$0.isEmpty ? nil:$0} ?? row["title"] ?? "Codex conversation",
                project:URL(fileURLWithPath:row["cwd"] ?? "").lastPathComponent,model:"Codex",
                state:.recorded,detail:"Last recorded: \(turn?["status"] ?? "unknown"). Live server unavailable.",
                parentID:parents[id].map{"codex:"+$0},updated:Date(timeIntervalSince1970:(Double(row["updated"] ?? "") ?? 0)/1000),openURL:nil,stale:true,silent:true)
        }
    }
}

actor AgentSources {
    private let fixture:FixtureAgentSource?=AppRuntime.fixture ? FixtureAgentSource():nil
    private let ephemeralCredentials:Bool
    private var transientCredentials:[String:String]=[:]
    init(ephemeralCredentials:Bool=false) {self.ephemeralCredentials=ephemeralCredentials}
    private func readCredential(_ account:String)->String? {ephemeralCredentials ? transientCredentials[account]:PikminKeychain.read(account)}
    private func saveCredential(_ value:String,account:String) throws {
        if ephemeralCredentials {transientCredentials[account]=value} else {try PikminKeychain.save(value,account:account)}
    }
    private func deleteCredential(_ account:String) {
        if ephemeralCredentials {transientCredentials.removeValue(forKey:account)} else {PikminKeychain.delete(account)}
    }
    private var fixtureConnected=true
    private var fixtureControls=true
    private var token:String?
    private var commandToken:String?
    private var accessLoaded=false
    private var questionClient:T3MCPClient?
    private var questionOrigin:String?
    private var lastSequence:Int = -1
    private var lastOrigin:String?
    private struct CachedOutput {
        var signature:String
        var readAt:Date
        var line:ConversationLine?
        var historical:Bool
    }
    private var recentOutput:[String:CachedOutput]=[:]
    private var outputRequests:[String:UUID]=[:]
    var connected:Bool {fixture != nil ? fixtureConnected:token != nil}
    var canOperate:Bool {fixture != nil ? fixtureControls:commandToken != nil}
    func loadSavedAccess() async throws {
        guard !accessLoaded else{return};accessLoaded=true
        guard fixture==nil,!ephemeralCredentials else{return}
        let saved=await Task.detached(priority:.utility) {(PikminKeychain.read("t3.token"),PikminKeychain.read("t3.commands.token"))}.value
        guard token==nil else{return}
        token=saved.0;commandToken=saved.1
        if token != nil {try await enableCommands()}
    }
    func connectT3() async throws {
        if fixture != nil {fixtureConnected=true;fixtureControls=true;return}
        if token != nil || commandToken != nil {try await disconnectT3()}
        let cli=FileManager.default.homeDirectoryForCurrentUser.appending(path:".t3/bin/t3").path
        let data=try await LocalProcessJob().run(executable:cli,arguments:["auth","session","issue","--scope","orchestration:read","--ttl",ephemeralCredentials ? "10m":"30d","--label",ephemeralCredentials ? "Pikminions live verification":"Pikminions","--json"])
        struct Issued:Decodable {var sessionId:String;var token:String}
        let issued=try JSONDecoder().decode(Issued.self,from:data)
        try await storeIssued(token:issued.token,sessionID:issued.sessionId,prefix:"t3",cli:cli)
        token=issued.token;lastSequence = -1
        try await enableCommands()
    }
    func disconnectT3() async throws {
        if let fixture {fixtureConnected=false;fixtureControls=false;await fixture.shutdown();return}
        token=nil;commandToken=nil;questionClient=nil
        recentOutput.removeAll();outputRequests.removeAll()
        for account in ["t3.token","t3.commands.token","t3.questions.token"] {deleteCredential(account)}
        var failed=false
        let cli=FileManager.default.homeDirectoryForCurrentUser.appending(path:".t3/bin/t3").path
        for account in ["t3.session","t3.commands.session","t3.questions.session"] {
            if let id=readCredential(account) {
                do {_=try await LocalProcessJob().run(executable:cli,arguments:["auth","session","revoke",id]);deleteCredential(account)}
                catch {failed=true}
            }
        }
        if failed {throw SourceFailure.message("Disconnected locally. T3 could not revoke every session; retry Disconnect when it is available.")}
    }
    private func origin() throws -> URL {
        guard !AppRuntime.fixture else {throw SourceFailure.message("Live connections are disabled in the fixture app.")}
        let path=FileManager.default.homeDirectoryForCurrentUser.appending(path:".t3/userdata/server-runtime.json")
        let data=try Data(contentsOf:path)
        struct Runtime:Decodable {var origin:String}
        let runtime=try JSONDecoder().decode(Runtime.self,from:data)
        guard let url=URL(string:runtime.origin),["127.0.0.1","localhost","::1"].contains(url.host ?? ""),url.scheme=="http" else {
            throw SourceFailure.message("Only the local T3 environment is enabled.")
        }
        if lastOrigin != url.absoluteString {lastSequence = -1;lastOrigin=url.absoluteString;recentOutput.removeAll();outputRequests.removeAll()}
        return url
    }
    func t3() async throws -> [AgentRecord] {
        if let fixture {guard fixtureConnected else {throw SourceFailure.message("Fixture source disconnected.")};return await fixture.snapshot()}
        guard let token else {throw SourceFailure.message("Connect to T3 to show your agents.")}
        let origin=try origin()
        var request=URLRequest(url:origin.appending(path:"api/orchestration/shell"))
        request.timeoutInterval=5
        request.setValue("Bearer "+token,forHTTPHeaderField:"Authorization")
        request.setValue("2",forHTTPHeaderField:"x-t3-orchestration-protocol")
        let (data,response)=try await URLSession.shared.data(for:request)
        guard let http=response as? HTTPURLResponse,http.statusCode==200 else {
            throw SourceFailure.message((response as? HTTPURLResponse)?.statusCode==401 ? "T3 access expired. Connect again." : "T3 is unavailable.")
        }
        guard data.count<10_485_760 else {throw SourceFailure.message("The T3 shell response is too large.")}
        let shell=try JSONDecoder().decode(T3Shell.self,from:data)
        guard shell.snapshotSequence>=lastSequence else {throw SourceFailure.message("A stale T3 snapshot was ignored.")}
        lastSequence=shell.snapshotSequence
        let descriptorURL=origin.appending(path:".well-known/t3/environment")
        let (descriptor,_)=try await URLSession.shared.data(from:descriptorURL)
        struct Environment:Decodable {var environmentId:String}
        let environment=try JSONDecoder().decode(Environment.self,from:descriptor)
        let projects=Dictionary(shell.projects.map{($0.id,$0.title)},uniquingKeysWith:{$1})
        let aliases=SQLiteMetadata.codexAliases()
        return shell.threads.filter{$0.archivedAt==nil && $0.deletedAt==nil}.map { thread in
            let state=mappedT3State(thread)
            let url=origin.appending(path:environment.environmentId).appending(path:thread.id)
            let held=thread.status=="completed" && state == .working
            var record=AgentRecord(id:"t3:"+thread.id,nativeID:thread.activeProviderThreadId.flatMap{aliases[$0]},
                source:"T3",threadID:thread.id,runID:thread.latestRunId ?? thread.activeRunId ?? "",title:thread.title,
                project:projects[thread.projectId] ?? "Project",model:thread.modelSelection?.model ?? "Agent",state:state,
                detail:held ? "Waiting for background agents." : state == .waitingInput ? "Your agent has a question." : state == .waitingApproval ? "Review the pending request in T3." : "",
                parentID:thread.lineage?.relationshipToParent=="subagent" ? thread.lineage?.parentThreadId.map{"t3:"+$0} : nil,
                updated:agentDate(state == .finished ? (thread.latestRunCompletedAt ?? thread.updatedAt):thread.updatedAt),openURL:url,silent:thread.latestRunSilent==true || thread.latestRunStopRequested==true,
                pendingRequestID:thread.pendingRuntimeRequest?.id,pendingRequestKind:thread.pendingRuntimeRequest?.kind,pendingRequestBlocking:thread.pendingRuntimeRequest?.blocking,output:thread.latestVisibleMessage?.role=="assistant" ? String((thread.latestVisibleMessage?.text ?? "").prefix(16000)):"",projectID:thread.projectId,outputMessageID:thread.latestVisibleMessage?.role=="assistant" ? thread.latestVisibleMessage?.id:nil,outputStreaming:thread.latestVisibleMessage?.streaming ?? false)
            if record.outputMessageID==nil {record=withRecentOutput(record)}
            return record
        }
    }
    /// The lightweight T3 shell intentionally omits message text. Read bounded
    /// conversations only for the visible squad, reuse unchanged results, and
    /// cap concurrent requests. Full histories are never retained here.
    func recentOutputs(for agents:[AgentRecord]) async ->[AgentRecord] {
        let candidates=Array(agents.filter{$0.source=="T3" && !$0.stale}.prefix(24))
        let now=Date.now
        let needed=candidates.filter {agent in
            guard let cached=recentOutput[agent.id] else{return true}
            return cached.signature != outputSignature(agent) || now.timeIntervalSince(cached.readAt)>(agent.state.isActive ? 8:60)
        }
        let requests=needed.map {agent ->(AgentRecord,UUID) in
            let id=UUID();outputRequests[agent.id]=id;return(agent,id)
        }
        await withTaskGroup(of:(AgentRecord,UUID,ConversationLine?,Bool).self) {group in
            var pending=requests.makeIterator()
            func enqueue(_ pair:(AgentRecord,UUID)) {
                group.addTask {
                    do {
                        let lines=try await self.conversation(for:pair.0)
                        try Task.checkCancellation()
                        return(pair.0,pair.1,lines.last(where:{$0.role=="assistant"}),false)
                    } catch {return(pair.0,pair.1,nil,true)}
                }
            }
            for _ in 0..<4 {if let pair=pending.next() {enqueue(pair)}}
            while let (agent,id,line,failed)=await group.next() {
                if outputRequests[agent.id]==id {
                    outputRequests.removeValue(forKey:agent.id)
                    if !failed,!Task.isCancelled {
                        let previous=recentOutput[agent.id]
                        let historical=previous.map{$0.line?.id==line?.id ? $0.historical:false} ?? (line?.streaming != true)
                        recentOutput[agent.id]=CachedOutput(signature:outputSignature(agent),readAt:.now,line:line,historical:historical)
                    }
                }
                if !Task.isCancelled,let pair=pending.next() {enqueue(pair)}
            }
        }
        if recentOutput.count>128 {
            let keep=Set(recentOutput.sorted{$0.value.readAt>$1.value.readAt}.prefix(128).map(\.key))
            recentOutput=recentOutput.filter{keep.contains($0.key)}
        }
        return candidates.map {agent in
            var result=withRecentOutput(agent)
            result.outputUnavailable=recentOutput[agent.id]==nil
            return result
        }
    }
    private func outputSignature(_ agent:AgentRecord)->String {agent.runID+"::"+agent.state.rawValue+"::"+String(agent.updated.timeIntervalSince1970)}
    private func withRecentOutput(_ agent:AgentRecord)->AgentRecord {
        guard let cached=recentOutput[agent.id],let line=cached.line else{return agent}
        var result=agent;result.output=line.text;result.outputMessageID=line.id;result.outputStreaming=line.streaming;result.outputHistorical=cached.historical
        return result
    }
    private func issueCredential(prefix:String,operate:Bool,mcp:Bool=false) async throws ->String {
        guard !AppRuntime.fixture else {throw SourceFailure.message("Credential issuance is disabled in the fixture app.")}
        guard token != nil else {throw SourceFailure.message("Connect T3 first.")}
        let cli=FileManager.default.homeDirectoryForCurrentUser.appending(path:".t3/bin/t3").path
        var arguments=["auth","session","issue","--scope","orchestration:read","--ttl",ephemeralCredentials ? "10m":"30d","--label",operate ? "Pikminions conversation controls":"Pikminions question reader","--json"]
        if operate {arguments += ["--scope","orchestration:operate"]}
        if mcp {arguments += ["--subject","mcp-client"]}
        let data=try await LocalProcessJob().run(executable:cli,arguments:arguments)
        struct Issued:Decodable {var sessionId:String;var token:String}
        let issued=try JSONDecoder().decode(Issued.self,from:data)
        try await storeIssued(token:issued.token,sessionID:issued.sessionId,prefix:prefix,cli:cli)
        return issued.token
    }
    func enableCommands() async throws {
        if fixture != nil {fixtureControls=true;return}
        guard commandToken==nil else{return}
        commandToken=try await issueCredential(prefix:"t3.commands",operate:true)
    }
    private func storeIssued(token:String,sessionID:String,prefix:String,cli:String) async throws {
        do {
            try Task.checkCancellation()
            try saveCredential(token,account:prefix+".token")
            try saveCredential(sessionID,account:prefix+".session")
        } catch {
            deleteCredential(prefix+".token");deleteCredential(prefix+".session")
            do {_=try await LocalProcessJob().run(executable:cli,arguments:["auth","session","revoke",sessionID])}
            catch {throw SourceFailure.message("T3 access could not be saved or fully revoked. Revoke the Pikminions session in T3 before reconnecting.")}
            throw error
        }
    }
    private func readQuestionClient() async throws ->T3MCPClient {
        let current=try origin()
        if let questionClient,questionOrigin==current.absoluteString {return questionClient}
        let credential:String
        if let saved=readCredential("t3.questions.token") {credential=saved}
        else {credential=try await issueCredential(prefix:"t3.questions",operate:false,mcp:true)}
        let client=T3MCPClient(origin:current,token:credential)
        questionClient=client;questionOrigin=current.absoluteString
        return client
    }
    func questions(for agent:AgentRecord) async throws ->AgentQuestionDocument {
        if let fixture {guard let document=await fixture.question(agent.threadID) else {throw SourceFailure.message("This fixture question is no longer pending.")};return document}
        guard agent.source=="T3",let requestID=agent.pendingRequestID else {throw SourceFailure.message("This host does not expose a pending question here. Open the conversation to answer it.")}
        return try await readQuestionClient().tool("t3_pending_request_read",arguments:["threadId":.string(agent.threadID),"requestId":.string(requestID)]).decoded(AgentQuestionDocument.self)
    }
    private func bounded(_ agent:AgentRecord) async throws ->JSONValue {
        if let fixture {return await fixture.projection(agent.threadID)}
        guard agent.source=="T3",let token else {throw SourceFailure.message("Live conversation output is unavailable for this source.")}
        var request=URLRequest(url:try origin().appending(path:"api/orchestration/threads/\(agent.threadID)/bounded"));request.timeoutInterval=8
        request.setValue("Bearer "+token,forHTTPHeaderField:"Authorization");request.setValue("2",forHTTPHeaderField:"x-t3-orchestration-protocol")
        let (data,response)=try await URLSession.shared.data(for:request)
        guard (response as? HTTPURLResponse)?.statusCode==200,data.count<10_485_760 else {throw SourceFailure.message("T3 could not load this conversation. Your draft is preserved.")}
        return try JSONDecoder().decode(JSONValue.self,from:data)
    }
    func conversation(for agent:AgentRecord) async throws ->[ConversationLine] {
        let snapshot=try await bounded(agent)
        return Self.projectionLines(snapshot["projection"])
    }
    /// Visible turn items include inherited fork history. `messages` contains
    /// only local records, and may carry text omitted from the visible row.
    static func projectionLines(_ projection:JSONValue?)->[ConversationLine] {
        let local=lines(projection?["messages"]?.array ?? [])
        let byID=Dictionary(local.map{($0.id,$0)},uniquingKeysWith:{_,new in new})
        let visible=(projection?["visibleTurnItems"]?.array ?? []).compactMap {row ->ConversationLine? in
            guard let item=row["item"],let type=item["type"]?.string,
                  ["assistant_message","user_message"].contains(type),let id=item["messageId"]?.string else{return nil}
            if item["textOmitted"]?.bool==true {return byID[id]}
            guard let text=item["text"]?.string else{return byID[id]}
            return ConversationLine(id:id,role:type=="assistant_message" ? "assistant":"user",text:String(text.prefix(24000)),streaming:item["streaming"]?.bool ?? false)
        }
        return visible.isEmpty ? local:Array(visible.suffix(30))
    }
    func canaryDiagnostics(_ agent:AgentRecord) async throws ->JSONValue {
        guard ephemeralCredentials,agent.title.hasPrefix("Pikminions TEST - "),let token else {throw SourceFailure.message("Diagnostics require a labeled RAM-only canary.")}
        var request=URLRequest(url:try origin().appending(path:"api/orchestration/shell"));request.timeoutInterval=8
        request.setValue("Bearer "+token,forHTTPHeaderField:"Authorization");request.setValue("2",forHTTPHeaderField:"x-t3-orchestration-protocol")
        let (data,_)=try await URLSession.shared.data(for:request)
        let shell=try JSONDecoder().decode(JSONValue.self,from:data)
        guard let thread=shell["threads"]?.array?.first(where:{$0["id"]?.string==agent.threadID}),case .object(let fields)=thread else {throw SourceFailure.message("The labeled canary is missing.")}
        let names=JSONValue.array(fields.keys.sorted().map(JSONValue.string))
        let keys=["status","activityRunStatus","latestRunId","activeRunId","latestVisibleMessage","latestAssistantMessage","pendingBackgroundTasks"]
        return .object(["fieldNames":names,"fields":.object(fields.filter{keys.contains($0.key)})])
    }
    static func lines(_ values:[JSONValue])->[ConversationLine] {
        values.suffix(30).compactMap {value in
            guard let id=value["id"]?.string,let role=value["role"]?.string,let text=value["text"]?.string,["user","assistant"].contains(role) else{return nil}
            return ConversationLine(id:id,role:role,text:String(text.prefix(24000)),streaming:value["streaming"]?.bool ?? false)
        }
    }
    /// Codex publishes partial assistant text as turn items; message.updated may
    /// only arrive at completion. Both records share the conversation message ID.
    static func eventLine(_ event:JSONValue,threadID:String)->ConversationLine? {
        guard let payload=event["payload"],payload["textOmitted"]?.bool != true,let text=payload["text"]?.string else{return nil}
        if let owner=payload["threadId"]?.string ?? event["threadId"]?.string,owner != threadID {return nil}
        let id:String,role:String
        switch event["type"]?.string {
        case "message.updated":
            guard let messageID=payload["id"]?.string,let messageRole=payload["role"]?.string,["user","assistant"].contains(messageRole) else{return nil}
            id=messageID;role=messageRole
        case "turn-item.updated":
            guard let kind=payload["type"]?.string,["assistant_message","user_message"].contains(kind),let messageID=payload["messageId"]?.string else{return nil}
            id=messageID;role=kind=="assistant_message" ? "assistant":"user"
        default:return nil
        }
        return ConversationLine(id:id,role:role,text:IslandMarkdown.tail(text,maxBytes:24000),streaming:payload["streaming"]?.bool ?? false,containsAccept:text.contains("ACCEPT"))
    }
    func conversationStream(for agent:AgentRecord,afterSequence:Double?=nil) async throws ->AsyncThrowingStream<JSONValue,Error> {
        if let fixture {return await fixture.stream(agent.threadID)}
        guard agent.source=="T3",let token else {throw SourceFailure.message("Live output is unavailable for this source.")}
        return try T3Socket.stream(origin:origin(),token:token,threadID:agent.threadID,afterSequence:afterSequence)
    }
    private func dispatch(_ command:JSONValue) async throws {
        if let fixture {guard fixtureControls else {throw SourceFailure.message("Reconnect the sample source to reply.")};try await fixture.dispatch(command);return}
        guard let commandToken else {throw SourceFailure.message("Reconnect T3 to restore replies and thread controls. Your draft is preserved.")}
        _=try await T3Socket.call(origin:origin(),token:commandToken,method:"orchestration.dispatchCommand",payload:command)
    }
    func answer(_ agent:AgentRecord,requestID:String,answers:[String:[String]],commandID:String) async throws {
        guard agent.isInteractive else {throw SourceFailure.message("This connection cannot answer standalone Codex requests. Open Codex to reply.")}
        guard agent.pendingRequestID==requestID else {throw SourceFailure.message("This question is no longer current. Refresh before answering.")}
        let snapshot=try await bounded(agent)
        let request=snapshot["projection"]?["runtimeRequests"]?.array?.first(where:{$0["id"]?.string==requestID})
        let capability=request?["responseCapability"]?["type"]?.string
        let asText=capability=="message" || (capability==nil && agent.pendingRequestBlocking==false)
        try await dispatch(AgentCommands.answer(threadID:agent.threadID,requestID:requestID,answers:answers,commandID:commandID,asText:asText))
    }
    func send(_ agent:AgentRecord,text:String,delivery:MessageDelivery,commandID:String,messageID:String) async throws {
        guard agent.isInteractive,!text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,text.utf8.count<=120000 else {throw SourceFailure.message("Choose a live T3 conversation and a message under 120 KB.")}
        try await dispatch(AgentCommands.message(threadID:agent.threadID,text:text,commandID:commandID,messageID:messageID,activeRunID:agent.state.isActive ? agent.runID:nil,delivery:delivery))
    }
    func fork(_ agent:AgentRecord,targetID:String,title:String,commandID:String) async throws {
        guard agent.isInteractive else {throw SourceFailure.message("Fork is unavailable for this source.")}
        try await dispatch(AgentCommands.fork(threadID:agent.threadID,targetID:targetID,title:title,commandID:commandID))
    }
    func fresh(_ agent:AgentRecord,targetID:String,title:String,commandID:String) async throws {
        let snapshot=try await bounded(agent)
        guard let thread=snapshot["projection"]?["thread"],let project=thread["projectId"],let model=thread["modelSelection"],let runtime=thread["runtimeMode"],let interaction=thread["interactionMode"] else {throw SourceFailure.message("T3 did not expose the setup needed for a new conversation.")}
        try await dispatch(.object(["type":.string("thread.create"),"commandId":.string(commandID),"threadId":.string(targetID),"projectId":project,"title":.string(title),"modelSelection":model,"runtimeMode":runtime,"interactionMode":interaction,"branch":thread["branch"] ?? .null,"worktreePath":thread["worktreePath"] ?? .null,"createdBy":.string("user"),"creationSource":.string("web")]))
    }
    func stop(_ agent:AgentRecord,commandID:String) async throws {
        guard agent.isInteractive else {throw SourceFailure.message("Stop is unavailable for this source.")}
        try await dispatch(AgentCommands.stop(threadID:agent.threadID,commandID:commandID))
    }
    func codex() async throws -> (records:[AgentRecord],live:Bool) {
        if fixture != nil {return([],false)}
        let home=FileManager.default.homeDirectoryForCurrentUser
        let socket=home.appending(path:".codex/app-server-control/app-server-control.sock")
        if FileManager.default.fileExists(atPath:socket.path) {
            do {
                let data=try await LocalProcessJob().run(executable:"/opt/homebrew/bin/codex",arguments:["app-server","proxy"],rpc:true)
                struct Page:Decodable {var data:[Thread]}
                struct Thread:Decodable {
                    var id:String;var name:String?;var cwd:String?;var status:Status
                    struct Status:Decodable {var type:String;var activeFlags:[String]?}
                }
                let page=try JSONDecoder().decode(Page.self,from:data)
                let records=page.data.map { thread -> AgentRecord in
                    let flags=thread.status.activeFlags ?? []
                    let state:AgentState=flags.contains("waitingOnApproval") ? .waitingApproval : flags.contains("waitingOnUserInput") ? .waitingInput : thread.status.type=="active" ? .working : thread.status.type=="systemError" ? .failed : .idle
                    return AgentRecord(id:"codex:"+thread.id,nativeID:thread.id,source:"Codex",threadID:thread.id,runID:thread.id,
                        title:thread.name ?? "Codex conversation",project:URL(fileURLWithPath:thread.cwd ?? "").lastPathComponent,
                        model:"Codex",state:state,detail:"",parentID:nil,updated:.now,openURL:nil,stale:thread.status.type=="notLoaded")
                }
                return(records,true)
            } catch { /* A failed shared-server read falls back to explicitly recorded history. */ }
        }
        return(try SQLiteMetadata.recordedCodex(),false)
    }
}
