import Foundation
import LuminaVaultShared

protocol WorkflowsClientProtocol: Sendable {
    func list() async throws -> WorkflowListResponse
    func runs(workflowID: UUID?) async throws -> WorkflowRunsResponse
    func approvals() async throws -> WorkflowApprovalsResponse
    func templates() async throws -> WorkflowTemplatesResponse
    func limits() async throws -> WorkflowLimitsDTO
    func runDetail(runID: UUID) async throws -> WorkflowRunDTO
    func events(runID: UUID) -> AsyncThrowingStream<WorkflowRunEventDTO, any Error>
    func run(workflowID: UUID, input: [String: String], conversationID: UUID?) async throws -> WorkflowRunDTO
    func runTemplate(templateID: String) async throws -> WorkflowRunDTO
    func cancel(runID: UUID) async throws
    func retry(runID: UUID) async throws -> WorkflowRunDTO
    func resume(runID: UUID) async throws -> WorkflowRunDTO
    func decide(approvalID: UUID, approved: Bool, memoryIDs: [UUID]) async throws
}

enum WorkflowsEndpoints {
    struct List: Endpoint { typealias Response = WorkflowListResponse; var path: String {
        "/v1/workflows"
    }; var method: HTTPMethod {
        .get
    } }
    struct Runs: Endpoint {
        typealias Response = WorkflowRunsResponse
        let workflowID: UUID?
        var path: String {
            workflowID.map { "/v1/workflows/\($0)/runs" } ?? "/v1/workflows/runs"
        }

        var method: HTTPMethod {
            .get
        }
    }

    struct Run: Endpoint {
        typealias Response = WorkflowRunDTO
        let workflowID: UUID; let request: WorkflowRunRequest
        var path: String {
            "/v1/workflows/\(workflowID)/runs"
        }; var method: HTTPMethod {
            .post
        }

        var body: (any Encodable)? {
            request
        }
    }

    struct Approvals: Endpoint { typealias Response = WorkflowApprovalsResponse; var path: String {
        "/v1/workflows/approvals"
    }; var method: HTTPMethod {
        .get
    } }
    struct Templates: Endpoint { typealias Response = WorkflowTemplatesResponse; var path: String {
        "/v1/workflow-templates"
    }; var method: HTTPMethod {
        .get
    } }
    struct Limits: Endpoint { typealias Response = WorkflowLimitsDTO; var path: String {
        "/v1/workflows/limits"
    }; var method: HTTPMethod {
        .get
    } }
    struct RunDetail: Endpoint {
        typealias Response = WorkflowRunDTO
        let runID: UUID
        var path: String {
            "/v1/workflows/runs/\(runID)"
        }

        var method: HTTPMethod {
            .get
        }
    }

    struct Events: StreamingEndpoint {
        typealias Event = WorkflowRunEventDTO
        let runID: UUID
        var path: String {
            "/v1/workflows/runs/\(runID)/events/stream"
        }

        var method: HTTPMethod {
            .get
        }
    }

    struct RunTemplate: Endpoint {
        typealias Response = WorkflowRunDTO
        let templateID: String
        var path: String {
            "/v1/workflow-templates/\(templateID)/runs"
        }

        var method: HTTPMethod {
            .post
        }

        var body: (any Encodable)? {
            WorkflowRunRequest(input: [:])
        }
    }

    struct RunAction: Endpoint {
        typealias Response = WorkflowRunDTO
        let runID: UUID
        let action: String
        var path: String {
            "/v1/workflows/runs/\(runID)/\(action)"
        }

        var method: HTTPMethod {
            .post
        }
    }

    struct Cancel: Endpoint {
        typealias Response = EmptyResponse
        let runID: UUID
        var path: String {
            "/v1/workflows/runs/\(runID)/cancel"
        }

        var method: HTTPMethod {
            .post
        }
    }

    struct Decide: Endpoint {
        typealias Response = EmptyResponse
        let approvalID: UUID; let request: WorkflowApprovalDecisionRequest
        var path: String {
            "/v1/workflows/approvals/\(approvalID)/decision"
        }; var method: HTTPMethod {
            .post
        }

        var body: (any Encodable)? {
            request
        }
    }
}

final class WorkflowsHTTPClient: WorkflowsClientProtocol {
    private let client: BaseHTTPClient
    init(client: BaseHTTPClient) {
        self.client = client
    }

    func list() async throws -> WorkflowListResponse {
        try await client.execute(WorkflowsEndpoints.List())
    }

    func runs(workflowID: UUID? = nil) async throws -> WorkflowRunsResponse {
        try await client.execute(WorkflowsEndpoints.Runs(workflowID: workflowID))
    }

    func approvals() async throws -> WorkflowApprovalsResponse {
        try await client.execute(WorkflowsEndpoints.Approvals())
    }

    func templates() async throws -> WorkflowTemplatesResponse {
        try await client.execute(WorkflowsEndpoints.Templates())
    }

    func limits() async throws -> WorkflowLimitsDTO {
        try await client.execute(WorkflowsEndpoints.Limits())
    }

    func runDetail(runID: UUID) async throws -> WorkflowRunDTO {
        try await client.execute(WorkflowsEndpoints.RunDetail(runID: runID))
    }

    func events(runID: UUID) -> AsyncThrowingStream<WorkflowRunEventDTO, any Error> {
        client.executeStream(WorkflowsEndpoints.Events(runID: runID))
    }

    func run(workflowID: UUID, input: [String: String] = [:], conversationID: UUID? = nil) async throws -> WorkflowRunDTO {
        try await client.execute(WorkflowsEndpoints.Run(workflowID: workflowID, request: WorkflowRunRequest(input: input, conversationID: conversationID)))
    }

    func runTemplate(templateID: String) async throws -> WorkflowRunDTO {
        try await client.execute(WorkflowsEndpoints.RunTemplate(templateID: templateID))
    }

    func cancel(runID: UUID) async throws {
        _ = try await client.execute(WorkflowsEndpoints.Cancel(runID: runID))
    }

    func retry(runID: UUID) async throws -> WorkflowRunDTO {
        try await client.execute(WorkflowsEndpoints.RunAction(runID: runID, action: "retry"))
    }

    func resume(runID: UUID) async throws -> WorkflowRunDTO {
        try await client.execute(WorkflowsEndpoints.RunAction(runID: runID, action: "resume"))
    }

    func decide(approvalID: UUID, approved: Bool, memoryIDs: [UUID] = []) async throws {
        _ = try await client.execute(WorkflowsEndpoints.Decide(
            approvalID: approvalID,
            request: WorkflowApprovalDecisionRequest(approved: approved, memoryIDs: memoryIDs)
        ))
    }
}
