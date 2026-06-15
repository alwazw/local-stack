"""
State Graph — LangGraph-pattern orchestration engine.
This is a pure-Python implementation of the CEO node graph that mirrors
how LangGraph would wire the same topology:

    [Intake] → [Scope Validation] → [PM Delegation]
                                       ├→ [Dev Agent Pool]
                                       └→ [DevOps Agent Pool]
    [Checkpoint] ← [Result Aggregation] ← [Sub-Agent Completion]

In production, each `node_fn` becomes a LangGraph node and each
conditional branch becomes a LangGraph conditional edge.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Callable

from .agents import DevAgent, DevOpsAgent, PMAgent
from .contract import check_approval_gate, simulate_hermes_signoff
from .state import GraphState, NodeStatus, SubAgentRole


@dataclass
class Edge:
    target: str
    condition: Callable[[GraphState], bool] | None = None


@dataclass
class GraphNode:
    name: str
    fn: Callable[[GraphState], GraphState]
    edges: list[Edge] = field(default_factory=list)


class CEOGraph:
    """
    Agent Zero's CEO orchestration graph.
    Nodes execute sequentially; conditional edges branch the flow.
    """

    def __init__(self):
        self.nodes: dict[str, GraphNode] = {}
        self._build_graph()

    def _build_graph(self):
        self._add_node("intake", self._intake, [Edge("scope_validation")])
        self._add_node(
            "scope_validation",
            self._scope_validation,
            [
                Edge("pm_delegation", condition=lambda s: s.contract_approved.hermes_signoff),
                Edge("blocked", condition=lambda s: not s.contract_approved.hermes_signoff),
            ],
        )
        self._add_node("pm_delegation", self._pm_delegation, [Edge("dev_pool")])
        self._add_node("dev_pool", self._dev_pool, [Edge("result_aggregation")])
        self._add_node(
            "result_aggregation",
            self._result_aggregation,
            [
                Edge("devops_pool", condition=lambda s: s.sandbox_verified),
                Edge("checkpoint", condition=lambda s: not s.sandbox_verified),
            ],
        )
        self._add_node("devops_pool", self._devops_pool, [Edge("checkpoint")])
        self._add_node("checkpoint", self._checkpoint, [])
        self._add_node("blocked", self._blocked, [])

    def _add_node(self, name: str, fn: Callable, edges: list[Edge]):
        self.nodes[name] = GraphNode(name=name, fn=fn, edges=edges)

    def run(self, state: GraphState) -> GraphState:
        """Execute the graph from intake to a terminal node."""
        current = "intake"

        while current:
            node = self.nodes[current]
            state.current_node = current
            state.node_history.append(current)

            state = node.fn(state)

            next_node = None
            for edge in node.edges:
                if edge.condition is None:
                    next_node = edge.target
                    break
                if edge.condition(state):
                    next_node = edge.target
                    break

            current = next_node

        return state

    # ── Node implementations ────────────────────────────────────────

    @staticmethod
    def _intake(state: GraphState) -> GraphState:
        state.project_name = state.contract.get("project", "unknown")
        return state

    @staticmethod
    def _scope_validation(state: GraphState) -> GraphState:
        state = check_approval_gate(state)

        if not state.contract_approved.hermes_signoff:
            state = simulate_hermes_signoff(state)
            state = check_approval_gate(state)

        return state

    @staticmethod
    def _pm_delegation(state: GraphState) -> GraphState:
        pm = PMAgent()
        result = pm.execute(state)
        state.sub_agent_results.append(result)
        return state

    @staticmethod
    def _dev_pool(state: GraphState) -> GraphState:
        pm_results = [r for r in state.sub_agent_results if r.role == SubAgentRole.PM]
        feature_count = 1
        if pm_results:
            feature_count = pm_results[0].output.get("feature_count", 1)

        dev_agents = [DevAgent(specialty="fullstack") for _ in range(min(feature_count, 3))]

        for dev in dev_agents:
            result = dev.execute(state)
            state.sub_agent_results.append(result)

        return state

    @staticmethod
    def _result_aggregation(state: GraphState) -> GraphState:
        dev_results = [r for r in state.sub_agent_results if r.role == SubAgentRole.DEV]
        all_passed = all(r.status == NodeStatus.COMPLETED for r in dev_results)
        state.sandbox_verified = all_passed

        if not all_passed:
            state.errors.append("Sandbox verification failed: one or more Dev agents reported failures")

        return state

    @staticmethod
    def _devops_pool(state: GraphState) -> GraphState:
        devops = DevOpsAgent()
        result = devops.execute(state)
        state.sub_agent_results.append(result)

        if result.status == NodeStatus.COMPLETED:
            state.deploy_manifest = result.output.get("deploy_manifest")

        return state

    @staticmethod
    def _checkpoint(state: GraphState) -> GraphState:
        if not state.errors:
            state.final_status = NodeStatus.COMPLETED
        else:
            state.final_status = NodeStatus.FAILED
        return state

    @staticmethod
    def _blocked(state: GraphState) -> GraphState:
        state.final_status = NodeStatus.BLOCKED
        return state
