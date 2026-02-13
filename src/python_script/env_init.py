import dill, sys

def FINAL_VAR(name):
    """Return the value of a variable as a final answer."""
    variable_name = name.strip().strip("\"'")
    if variable_name in globals():
        return str(globals()[variable_name])
    return None

def FINAL(name):
    """Return the value as a final answer."""
    return str(name)

code = sys.argv[1]
context = sys.argv[2] if len(sys.argv) > 2 else ""

try:
    dill.load_session("env.dill")
except FileNotFoundError:
    pass

exec(code)

del code

dill.dump_session("env.dill")

