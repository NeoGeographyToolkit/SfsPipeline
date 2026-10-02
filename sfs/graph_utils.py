import numpy as np
import networkx as nx
from collections import Counter

def degree_histogram(G):
    # Get degrees of all nodes
    degrees = [deg for _, deg in G.degree()]
    # get the counter to count how many times each degree occurs
    c = Counter(degrees)
    # get the sorted keys for the counter
    keys = sorted(c.keys())
    # make the dict. Ensure keys are strings for json
    degree_histogram = {str(k): c[k] for k in keys}
    return degree_histogram

def prune_to_mst(pairs, match_counts):
    """
    return the maximum spanning tree for the graph, using weights that are the 
    match counts from match counts
    I'll need to look into how to get the counts for matches prior to actually running optimization...
    """
    # make the graph
    G = nx.Graph()
    # add the edges with weights TODO make counts unique integers to use Boruvka algo
    G.add_edges_from(np.hstack((pairs, match_counts)))
    # Compute the maximum spanning tree (MST)
    mst = nx.maximum_spanning_tree(G, weight='weight')
    # determine if it's connected
    connected = nx.is_connected(mst)
    # get the weakly connected components
    components = list(nx.connected_components(mst))
    components_graphs = [mst.subgraph(c).copy() for c in components]
    return connected, components, components_graphs


def check_connectivity(pairs):
    """
    construct the newtorkx graph and determine if there is connectivity or not
    """
    # make the graph
    G = nx.Graph()
    # add the edges
    G.add_edges_from(pairs)
    ## perform checks
    # get the weakly connected components
    components = list(nx.connected_components(G))
    components = sorted(components, key=len, reverse=True)
    # get the size of each
    components_sizes = list(map(len, components))
    # if you have more than one component, the bundle adjustment network
    # is incomplete (islands of data)
    # This is probably a bad thing, but it doesn't mean that within each 
    # island (component), the data isn't good, it just means that there is no
    # guarentee it is co-aligned to the other components
    # likely the best path forward is to take the largest of these and use that only
    # or to treat each connected component as a isolated part and independently do stereo
    # and pc_align for each
    #
    # components is a set so construct a new graph per component
    components_graphs = [G.subgraph(c).copy() for c in components]
    return {
        'components': [list(_) for _ in components],
        'is_connected': nx.is_connected(G),
        'num_pairs': len(pairs),
        'num_components': len(components_sizes),
        'component_sizes': components_sizes,
        'num_pairs_per_component': [nx.number_of_edges(_) for _ in components_graphs],
        'degree_hist_per_component': [degree_histogram(_) for _ in components_graphs]
    }

