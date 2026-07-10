import Foundation
import LuminaVaultShared

protocol WorkflowsClientProtocol: Sendable {
    func list() async throws -> WorkflowListResponse
    func runs(workflowID: UUID?) async throws -> WorkflowRunsResponse
    func approvals() async throws -> WorkflowApprovalsResponse
    func run(workflowID: UUID, input: [String: String], conversationID: UUID?) async throws -> WorkflowRunDTO
    func decide(approvalID: UUID, approved: Bool) async throws
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

    func run(workflowID: UUID, input: [String: String] = [:], conversationID: UUID? = nil) async throws -> WorkflowRunDTO {
        try await client.execute(WorkflowsEndpoints.Run(workflowID: workflowID, request: WorkflowRunRequest(input: input, conversationID: conversationID)))
    }

    func decide(approvalID: UUID, approved: Bool) async throws {
        _ = try await client.execute(WorkflowsEndpoints.Decide(approvalID: approvalID, request: WorkflowApprovalDecisionRequest(approved: approved)))
    }
}
