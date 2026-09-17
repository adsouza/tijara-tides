"""Canonical external route data without changing the order of a traveled path."""
import searoute


def canonical_network(nodes, edges):
    # Both nearest-node ties (KD tree) and equal-cost paths (Dijkstra) depend on
    # insertion order. Fix it before routing, not by sorting the resulting path.
    nodes = {point: dict(nodes[point]) for point in sorted(nodes)}
    edges = {
        point: {neighbor: dict(edges[point][neighbor]) for neighbor in sorted(edges[point])}
        for point in sorted(edges)
    }
    return searoute.from_nodes_edges_set(searoute.Marnet(), nodes, edges)


def canonical_passages(passages):
    # Passages are membership metadata, not a traversal itinerary.
    return sorted(set(passages))


def canonical_canal_edges(edges):
    return sorted(
        ({'from': list(a), 'to': list(b), 'passage': values['passage']}
         for a, neighbors in edges.items() for b, values in neighbors.items()
         if values.get('passage') in ('panama', 'suez')),
        key=lambda edge: (edge['passage'], edge['from'], edge['to']),
    )
