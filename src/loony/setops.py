import re

import fire
import pandas as pd
from lark import Lark, Transformer

LROC_PID = r'\b([MECS]\d{9}[RLMCVU]E)\b'

# TODO Idea:
# add a flag to parse out the product ids in the readme following regex

grammar = r"""
?start: expr

?expr: expr OP_CARET expr       -> symdiff
     | expr SYMMETRIC expr      -> symdiff
     | expr OP_MINUS expr       -> diff
     | expr DIFFERENCE expr     -> diff
     | expr OP_VBAR expr        -> union
     | expr UNION expr          -> union
     | expr OP_AND expr         -> intersection
     | expr INTERSECTION expr   -> intersection
     | expr ISSUBSET expr       -> issubset
     | expr OP_LTE expr         -> issubset
     | expr OP_LT expr          -> issubset_proper
     | expr ISSUPERSET expr     -> issuperset
     | expr OP_GTE expr         -> issuperset
     | expr OP_GT expr          -> issuperset_proper
     | expr OP_NE expr          -> isdisjoint
     | expr ISDISJOINT expr     -> isdisjoint
     | expr OP_EQ expr          -> isequal
     | expr EQUALS expr         -> isequal
     | term

?term: IDENTIFIER index?        -> file
     | "(" expr ")"

index: "[" NUMBER "]"

OP_MINUS: "-"
OP_CARET: "^"
OP_VBAR: "|"
OP_AND: "&"
OP_LT: "<"
OP_GT: ">"
OP_LTE: "<="
OP_GTE: ">="
OP_NE: "_"
OP_EQ: "=="
EQUALS: "isequal"
UNION: "union"
INTERSECTION: "intersection"
DIFFERENCE: "difference"
SYMMETRIC: "symmetric_difference"
ISSUBSET: "issubset"
ISSUBSETPROPER: "issubset_proper"
ISSUPERSET: "issuperset"
ISSUPERSETPROPER: "issuperset_proper"
ISDISJOINT: "isdisjoint"


IDENTIFIER: /[a-zA-Z_]\w*/
NUMBER: /\d+/

%import common.WS
%ignore WS
"""

class SetTransformer(Transformer):
    def isequal(self, items):
        left, op, right = items
        return ("isequal", left, right)

    def symdiff(self, items):
        left, op, right = items
        return ("symdiff", left, right)

    def diff(self, items):
        left, op, right = items
        return ("diff", left, right)
    
    def union(self, items):
        left, op, right = items
        return ("union", left, right)
    
    def isdisjoint(self, items):
        left, op, right = items
        return ("isdisjoint", left, right)
    
    def intersection(self, items):
        left, op, right = items
        return ("intersection", left, right)

    def issubset(self, items):
        left, op, right = items
        return ("issubset", left, right)
    
    def issubset_proper(self, items):
        left, op, right = items
        return ("issubset_proper", left, right)
    
    def issuperset(self, items):
        left, op, right = items
        return ("issuperset", left, right)

    def issuperset_proper(self, items):
        left, op, right = items
        return ("issuperset_proper", left, right)

    def file(self, items):
        # items[0] is the file identifier; items[1] is optional index.
        name = items[0]
        if len(items) > 1:
            return ("file", name, items[1])
        return ("file", name)

    def index(self, items):
        # Return the integer value for the index.
        return items[0]

    def NUMBER(self, token):
        return int(token)

    def IDENTIFIER(self, token):
        return str(token)

# Use the Earley parser to allow left recursion in our grammar.
parser = Lark(grammar, parser="earley")

# parse the expression
def parse_expression(expr):
    # First, parse the expression to obtain a parse tree.
    parse_tree = parser.parse(expr)
    # Then, apply the transformer in a separate step.
    transformer = SetTransformer()
    return transformer.transform(parse_tree)


def evaluate(ast, file_data, bypid: bool = False):
    """
    Evaluates the AST using the file_data dictionary.
    
    file_data should be a dict mapping file identifiers (like "f1") to their pandas dataframes
    """
    if isinstance(ast, tuple):
        node_type = ast[0]
        if node_type == "file":
            file_name = ast[1]
            # If only the file name is provided, treat the file as a simple list.
            if len(ast) == 2:
                # Convert the list to a set.
                vals = set(file_data[file_name][0].values.tolist())
            # If an index is provided, treat the file data as CSV rows and extract the specified column.
            elif len(ast) == 3:
                col_index = ast[2]
                vals = set(file_data[file_name][col_index].values.tolist())
            else:
                raise ValueError(f'Unknown options provided to file: {ast}')
            if bypid:
                _vals = []
                for s in vals:
                    match = re.search(LROC_PID, s)
                    if match:
                        _vals.append(match.group(0))
                return set(_vals)
            else:
                return vals
        else:
            left:  set = evaluate(ast[1], file_data, bypid=bypid)
            right: set = evaluate(ast[2], file_data, bypid=bypid)
            if node_type == "diff":
                return left.difference(right)
            elif node_type == "symdiff":
                return left.symmetric_difference(right)
            elif node_type == "isdisjoint":
                return left.isdisjoint(right)
            elif node_type == "union":
                return left.union(right)
            elif node_type == "intersection":
                return left.intersection(right)
            elif node_type == "issubset":
                return left.issubset(right)
            elif node_type == "issubset_proper":
                return left < right
            elif node_type == "issuperset":
                return left.issuperset(right)
            elif node_type == "issuperset_proper":
                return left > right
            elif node_type == "isequal":
                return left == right
            else:
                raise ValueError(f"Unknown operation: {node_type}")       
    else:
        raise ValueError(f"Invalid AST node: {ast}")

def read_file(path, header=None)-> pd.DataFrame:
    """
    Read the path as a file to the expected 

    :param path: _description_
    :return: _description_
    """
    # TODO finish this, clearly won't work, maybe allow other stuff in grammar to allow opts to pass to read_csv?
    # implement different parsers for each file kind
    if 'convergence_angles' in path:
        return pd.read_csv(path, skiprows=2, header=None, sep=' ')
    elif 'mapproj_match_offset_pair_stats' in path:
        return pd.read_csv(path, skiprows=3, header=None, sep=' ')
    elif 'residuals_stats' in path:
        return pd.read_csv(path, skiprows=2, header=None, sep=' ')
    elif 'mapproj_match_offset_stats' in path:
        return pd.read_csv(path, skiprows=2, header=None, sep=' ')
    elif 'triangulation_offsets' in path:
        return pd.read_csv(path, skiprows=2, header=None, sep=' ')
    else:
        return pd.read_csv(path, header=header)



# main body
def run_expression(expr: str, *files: str, bypid: bool = False, verbose: bool = False):
    """
    Set Operations with ASP list files and normal text files for LROC

    :param expr: set operations to run in a python string
    :param bypid: if True match on and return Product IDs instead of full strings
    :param verbose: if True print extra logs (don't redirect stdout to file!)
    :return: 
    """
    # parse the expression
    ast = parse_expression(expr)
    if verbose:
        print(f"Expression: {expr}\nAST: {ast}\n")
    # read in the files
    if verbose:
        print(f"Provided {files}")
    files_data = {f'f{i}': read_file(file) for i, file in enumerate(files,start=1)}
    if verbose:
        print(f"Loaded {len(files_data)}: {list(files_data.keys())}")
        print(files_data)
    # evaluate the expression  
    result = evaluate(ast, files_data, bypid=bypid)
    # if we have a set, print it, else return True/False
    if isinstance(result, set):
        for _ in sorted(result):
            print(_, flush=True)
    else:
        return result

# main
def main():
    fire.Fire(run_expression)

if __name__ == '__main__':
    main()