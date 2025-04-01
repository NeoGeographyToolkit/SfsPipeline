from typing import List, Set
import warnings
warnings.filterwarnings('ignore', category=FutureWarning)

import numpy as np
import shapely
import networkx as nx
import networkx.algorithms.approximation as nx_app
import geopandas as gp


def spherical_to_cartesian(az_deg: np.ndarray | float, elev_deg:np.ndarray | float) -> np.ndarray:
    # Convert degrees to radians
    az = np.deg2rad(az_deg)
    elev = np.deg2rad(elev_deg)
    # Convert to Cartesian coordinates
    elv_cos = np.cos(elev)
    x = elv_cos * np.cos(az)
    y = elv_cos * np.sin(az)
    z = np.sin(elev)
    return np.array([x, y, z])

def angular_distance(az1_deg: np.ndarray | float, elev1_deg: np.ndarray | float, az2_deg: np.ndarray | float, elev2_deg: np.ndarray | float):
    # Convert each spherical coordinate to a Cartesian unit vector
    vec1 = spherical_to_cartesian(az1_deg, elev1_deg)
    vec2 = spherical_to_cartesian(az2_deg, elev2_deg)
    # Compute the dot product
    dot = np.dot(vec1, vec2)
    # Clip dot product to avoid numerical issues (should be in [-1, 1])
    dot = np.clip(dot, -1.0, 1.0)
    # Compute and return the angular distance in radians
    return np.arccos(dot)

def remove_duplicate_indexes(indexes: np.ndarray)-> np.ndarray:
    """
    _summary_

    :param indexes: _description_
    :return: _description_
    """
    x = []
    for _ in indexes:
        if _ not in x:
            x.append(_)
    return np.array(x)


def df_to_weighted_graph(
        df: gp.GeoDataFrame,
        reversed_order_penalty: int = 2,
        non_adjacent_penalty: int = 100,
        same_node_penalty: int = 2000,
        )-> nx.Graph:
    """
    _summary_

    :param df: _description_
    :return: _description_
    """
    # first construct the adjacency matrix 
    geoms = np.array(df.geometry.to_list())
    adjacency = intersect_group(geoms)
    # next get the sshd_diff, TODO use the cartesian distance for sshd and incidence angle
    sshd_diff = pairwise_diff_column(df)
    # construct the graph object
    G = nx.Graph()
    # grab the indexes from the df for later reconstruction
    indexes = df.index.to_numpy()
    # # Iterate over each unique pair of polygons to add an edge.
    for i in range(len(df)):
        for j in range(len(df)):
            # Begin constructing the weight by grabbing the diff of the sshd between the two
            weight = sshd_diff[i, j] 
            # if the sshd goes down to obs #2 (eg from 2 to 1), increase the weight
            if weight < 0:
                weight = (np.abs(weight)**2)*reversed_order_penalty
            # if the nodes don't intersect, add the penalty for that
            if not adjacency[i, j]:
                weight += non_adjacent_penalty
            # if the nodes are the same node, add the penalty for that
            if i == j:
                weight += same_node_penalty
            # finally add the edge
            G.add_edge(indexes[i], indexes[j], weight=weight)
    # finally return the graph
    return G


def solve_tsp(G: nx.Graph)-> np.ndarray:
    """
    _summary_

    :param df: _description_
    :return: cycle of index integers for the df
    """
    # solve the TSP using networkx
    cycle = nx_app.traveling_salesman_problem(
        G,
        weight='weight'
    )
    # convert cycle to numpy and remove repeated indexes 
    indexes = remove_duplicate_indexes(np.array(cycle))
    # return the indexes
    return indexes


def get_graph_order_weighted(adjacency: np.ndarray, weights: np.ndarray) -> List[int]:
    """
    Construct an undirected graph from a boolean adjacency matrix and compute an ordering
    of its nodes using a greedy heuristic based on polygon intersections.
    
    Each node in the graph represents a polygon, and an edge between two nodes indicates that
    the corresponding polygons intersect.
    
    Parameters
    ----------
    adjacency : np.ndarray
        A 2D boolean numpy array where adjacency[i, j] is True if polygon i intersects polygon j.
    
    Returns
    -------
    List[int]
        An ordering of polygon indices determined by a greedy intersection heuristic.
    """
    # Create an empty undirected graph.
    G: nx.Graph = nx.Graph()

    # Determine the number of polygons (assumes the adjacency matrix is square).
    num_polygons: int = adjacency.shape[0]

    # Add each polygon as a node in the graph with its corresponding weight.
    for i in range(num_polygons):
        G.add_node(i, weight=weights[i])

    # Iterate over each unique pair of polygons to add an edge if they intersect.
    for i in range(num_polygons):
        for j in range(i + 1, num_polygons):
            if adjacency[i, j]:
                # Add an undirected edge between polygons i and j.
                G.add_edge(i, j)

    # Compute the ordering of nodes using the greedy intersection heuristic.
    order: List[int] = greedy_intersection_order_weighted(G, weight_attr='weight')
    
    return order


def greedy_intersection_order_weighted(G: nx.Graph, weight_attr: str = "weight") -> List[int]:
    """
    Compute an ordering of nodes in a weighted graph that attempts to produce a sequence
    with mostly monotonically increasing weight values (small positive differences)
    between consecutive nodes. Connectivity is used when possible but is secondary to
    keeping weight differences low.
    
    The heuristic works by:
        1. Starting at the node with the smallest weight.
        2. At each step, looking among unvisited neighbors (if any) for those whose
           weight is at least that of the current node. If one or more exist, the one with
           the smallest weight difference is chosen.
        3. If no neighbor qualifies, then all unvisited nodes are considered: if any have
           a weight at least that of the current node, we choose the one with the smallest
           positive difference. Otherwise, we pick the unvisited node with the smallest
           absolute difference.
    
    Parameters
    ----------
    G : nx.Graph
        An undirected graph where nodes represent items (e.g. polygons) and edges indicate
        intersections.
    weight_attr : str, optional
        The node attribute to be used as the weight, by default "weight".
    
    Returns
    -------
    List[int]
        A list of node indices representing the order in which the nodes are visited.
    """
    # Get a list of all nodes.
    nodes: List[int] = list(G.nodes())
    
    # Keep track of visited nodes.
    visited: Set[int] = set()
    
    # List to store the computed ordering.
    order: List[int] = []
    
    # Start with the node that has the smallest weight.
    current: int = min(G.nodes, key=lambda n: G.nodes[n][weight_attr])
    order.append(current)
    visited.add(current)
    
    while len(visited) < len(nodes):
        # First try to use connectivity: among unvisited neighbors, pick one with a weight
        # greater than or equal to current, and with minimal difference.
        unvisited_neighbors = [
            n for n in G.neighbors(current)
            if n not in visited and G.nodes[n][weight_attr] >= G.nodes[current][weight_attr]
        ]
        
        if unvisited_neighbors:
            next_node = min(
                unvisited_neighbors,
                key=lambda n: G.nodes[n][weight_attr] - G.nodes[current][weight_attr]
            )
        else:
            # If no qualifying neighbor is available, consider all unvisited nodes.
            remaining = list(set(nodes) - visited)
            # First, see if any unvisited node has weight >= current.
            above = [
                n for n in remaining
                if G.nodes[n][weight_attr] >= G.nodes[current][weight_attr]
            ]
            if above:
                next_node = min(
                    above,
                    key=lambda n: G.nodes[n][weight_attr] - G.nodes[current][weight_attr]
                )
            else:
                # Otherwise, choose the one with the smallest absolute difference.
                next_node = min(
                    remaining,
                    key=lambda n: abs(G.nodes[n][weight_attr] - G.nodes[current][weight_attr])
                )
        
        order.append(next_node)
        visited.add(next_node)
        current = next_node
        
    return order


def get_graph_order(adjacency: np.ndarray) -> List[int]:
    """
    Construct an undirected graph from a boolean adjacency matrix and compute an ordering
    of its nodes using a greedy heuristic based on polygon intersections.
    
    Each node in the graph represents a polygon, and an edge between two nodes indicates that
    the corresponding polygons intersect.
    
    Parameters
    ----------
    adjacency : np.ndarray
        A 2D boolean numpy array where adjacency[i, j] is True if polygon i intersects polygon j.
    
    Returns
    -------
    List[int]
        An ordering of polygon indices determined by a greedy intersection heuristic.
    """
    # Create an empty undirected graph.
    G: nx.Graph = nx.Graph()
    
    # Determine the number of polygons (assumes the adjacency matrix is square).
    num_polygons: int = adjacency.shape[0]
    
    # Add each polygon as a node in the graph.
    for i in range(num_polygons):
        G.add_node(i)
    
    # Iterate over each unique pair of polygons to add an edge if they intersect.
    for i in range(num_polygons):
        for j in range(i + 1, num_polygons):
            if adjacency[i, j]:
                # Add an undirected edge between polygons i and j.
                G.add_edge(i, j)
    
    # Compute the ordering of nodes using the greedy intersection heuristic.
    order: List[int] = greedy_intersection_order(G)
    
    return order


def greedy_intersection_order(G: nx.Graph) -> List[int]:
    """
    Compute an ordering of nodes in an unweighted graph based on a greedy heuristic that
    prioritizes nodes with the highest number of intersections (neighbors).
    
    The heuristic works by:
        1. Starting at the node with the highest degree.
        2. Iteratively moving to an unvisited neighbor with the highest degree.
        3. If no unvisited neighbors remain, arbitrarily selecting any unvisited node.
    
    Note
    ----
    This approach does not guarantee a Hamiltonian path even if one exists, but it attempts
    to follow intersecting paths as far as possible.
    
    Parameters
    ----------
    G : nx.Graph
        An undirected graph where nodes represent polygons and edges indicate intersections.
    
    Returns
    -------
    List[int]
        A list of node indices representing the order in which the polygons are visited.
    """
    # List of all nodes in the graph.
    nodes: List[int] = list(G.nodes())
    
    # Set to track visited nodes.
    visited: Set[int] = set()
    
    # List to store the computed ordering.
    order: List[int] = []
    
    # Choose the starting node as the one with the highest degree (most intersections).
    current: int = max(G.degree, key=lambda x: x[1])[0]
    order.append(current)
    visited.add(current)
    
    # Continue until all nodes have been visited.
    while len(visited) < len(nodes):
        # Retrieve all unvisited neighbors of the current node.
        unvisited_neighbors: List[int] = [n for n in G.neighbors(current) if n not in visited]
        
        if unvisited_neighbors:
            # Choose the unvisited neighbor with the highest degree.
            next_node: int = max(unvisited_neighbors, key=lambda n: G.degree(n))
        else:
            # If no unvisited neighbors are available, select an arbitrary unvisited node.
            remaining: List[int] = list(set(nodes) - visited)
            next_node = remaining[0]
        
        # Add the selected node to the ordering and mark it as visited.
        order.append(next_node)
        visited.add(next_node)
        
        # Update the current node to the newly selected node.
        current = next_node
        
    return order

def intersect_group(geoms: np.ndarray) -> np.ndarray:
    """
    Compute the symmetric adjacency matrix of intersections for a collection of geometries.

    Each element (i, j) in the returned boolean matrix is True if and only if geoms[i] intersects
    with geoms[j]. The function computes the lower triangle of the matrix (excluding the diagonal)
    in a vectorized fashion by testing each geometry against the subarray of preceding geometries,
    then mirrors the lower triangle to produce the full symmetric matrix.

    Parameters:
        geoms (np.ndarray): A numpy array of Shapely geometry objects.

    Returns:
        np.ndarray: A boolean numpy array of shape (n, n) where n is the number of geometries.
    """
    n = geoms.shape[0]
    intersections = np.zeros((n, n), dtype=bool)
    
    # For each geometry starting from the second one, compute intersections with all previous geometries.
    for i in range(1, n):
        # Test the i-th geometry against all geometries in geoms[0:i] in one call.
        intersections[i, :i] = shapely.intersects(geoms[i], geoms[:i])
    
    # Mirror the lower triangle to the upper triangle to ensure the matrix is symmetric.
    intersections = intersections | intersections.T
    return intersections

def pairwise_diff_column(df: gp.GeoDataFrame, column='ROI_SUB_SOLAR_GROUND_AZIMUTH'):
    """
    _summary_

    :param df: _description_
    :param column: _description_, defaults to ''
    """
    data = df[column].to_numpy()
    n = data.shape[0]
    diff = np.zeros((n, n), dtype=float)
    for i in range(n):
        # TODO have the diff be negative if the 2nd value is larger than the first
        diff[i, :] = -(data[i] - data)
    return diff


def reorder_gdf_by_SSGA_TSP(in_gdf: gp.GeoDataFrame, chunksize: int = 50)-> gp.GeoDataFrame:
    """
    """
    new_index = []
    for chunk in list(np.array_split(in_gdf,len(in_gdf)//chunksize)):
        # get graph
        g_batch = df_to_weighted_graph(chunk)
        # get indexes
        i_batch = solve_tsp(g_batch)
        # accumulate the indexes
        new_index.append(i_batch)
    # get the new index as an array
    new_index = np.concatenate(new_index)  
    # sort 
    sorted_df = in_gdf.reindex(new_index).reset_index(drop=True)
    return sorted_df

def reorder_gdf_by_SSGA_INT(in_gdf: gp.GeoDataFrame, quantile_cut: int = 90)-> gp.GeoDataFrame:
    """
    _summary_

    :param gdf: _description_
    :return: _description_
    """
    # copy the df
    gdf = in_gdf.copy()
    # get the crs
    crs = gdf.crs
    # compute the quantile bins
    gdf['SSGA_BIN']=gp.pd.qcut(gdf['ROI_SUB_SOLAR_GROUND_AZIMUTH'], quantile_cut)
    bins = gdf['SSGA_BIN'].dtype.categories
    results = []
    for bin in bins:
        # get group
        dfg=gdf[gdf['SSGA_BIN'] == bin].copy().reset_index()
        # get adjacency
        adjacency = intersect_group(dfg.geometry)
        # get SSGA
        ssga = dfg['ROI_SUB_SOLAR_GROUND_AZIMUTH']
        # get the new weighted order
        new_order = get_graph_order_weighted(adjacency, ssga)
        # reset the index of the reordered sub group
        dfg=dfg.reindex(new_order).reset_index()
        # get the lagged geometries in the sub group
        _ = gp.GeoSeries([*dfg.geometry[1:].to_list(), dfg.geometry[0]], crs=crs)
        # compute if the next row intersects
        dfg['in_group_isect'] = dfg.geometry.intersects(_, align=False)
        # accumulate the results
        results.append(dfg)
    # combine all prior bins
    sorted_df = gp.pd.concat(results).reset_index(drop=True)
    # get the lagged geometries 
    lagged = gp.GeoSeries([*sorted_df.geometry[1:].to_list(), sorted_df.geometry[0]], crs=crs)
    # compute if the next row intersects
    sorted_df['next_isect'] = sorted_df.geometry.intersects(lagged, align=False)
    # done
    return sorted_df