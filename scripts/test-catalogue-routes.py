#!/usr/bin/env python3
"""Regression checks for external ordering and equal-cost route ties."""
import random
import unittest
from catalogue_routes import canonical_network, canonical_passages, canonical_canal_edges


class CanonicalRoutesTest(unittest.TestCase):
    def test_shuffled_nodes_neighbors_and_edges_choose_the_same_path(self):
        a, b, c, d = (0, 0), (1, -1), (1, 1), (2, 0)
        nodes = {p: {'x': p[0], 'y': p[1]} for p in [a, b, c, d]}
        edges = {a: {b: {'weight': 1}, c: {'weight': 1}},
                 b: {a: {'weight': 1}, d: {'weight': 1}},
                 c: {a: {'weight': 1}, d: {'weight': 1}},
                 d: {b: {'weight': 1}, c: {'weight': 1}}}
        expected = canonical_network(nodes, edges).shortest_path(a, d)
        nearest = canonical_network(nodes, edges).kdtree.query((1, 0))
        for seed in range(20):
            rng = random.Random(seed)
            def shuffle(mapping):
                items = list(mapping.items())
                rng.shuffle(items)
                return dict(items)
            graph = canonical_network(shuffle(nodes), shuffle({p: shuffle(e) for p, e in edges.items()}))
            length, path = graph.shortest_path(a, d)
            self.assertEqual((length, path), expected)
            self.assertEqual(graph.kdtree.query((1, 0)), nearest)
            self.assertEqual((path[0], path[-1]), (a, d))
            self.assertTrue(all(v in edges[u] for u, v in zip(path, path[1:])))

    def test_unordered_metadata_has_canonical_serialization(self):
        self.assertEqual(canonical_passages(['suez', 'panama', 'suez']), ['panama', 'suez'])
        edges = {(2, 1): {(0, 1): {'passage': 'suez'}},
                 (0, 1): {(2, 1): {'passage': 'panama'}}}
        self.assertEqual(canonical_canal_edges(edges), canonical_canal_edges(dict(reversed(list(edges.items())))))
        self.assertEqual(canonical_canal_edges(edges)[0]['passage'], 'panama')


if __name__ == '__main__':
    unittest.main()
