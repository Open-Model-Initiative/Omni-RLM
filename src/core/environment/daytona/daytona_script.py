# DEPRECATED: This script is deprecated and will be removed in future versions. Please use the `daytona` CLI tool or the Daytona Python SDK directly for interacting with Daytona environments.
from daytona import Daytona, DaytonaConfig
import argparse

parser = argparse.ArgumentParser(description="Run Daytona operations")
parser.add_argument("api_key", help="API key for Daytona")
parser.add_argument("--api-url", help="API URL for Daytona (optional)", default="https://app.daytona.io/api")
parser.add_argument("--container-id", "-c", help="Container ID (optional)", default=None)
parser.add_argument("--code", help="Code to execute in Daytona environment(optional)", default=None)
parser.add_argument("delete", help="Delete the container after execution", nargs='?', default=False, const=True)
parser.add_argument("--prompt", help="Prompt to run in Daytona environment (optional)", default=None)
parser.add_argument("--find_final_answer", help="Find final answer in the Daytona environment", default=False)
args = parser.parse_args()

api_key = args.api_key
api_url = args.api_url
container_id = args.container_id
code = args.code
delete = args.delete
prompt = args.prompt
find_final_answer = args.find_final_answer

config = DaytonaConfig(api_key=api_key, api_url=api_url)
client = Daytona(config = config)

init_code = '''
import re
final_var_pattern = r"^\\s*FINAL(_VAR)?\\((.*?)\\)"
def FINAL_VAR(name):
    variable_name = name.strip().strip("\\"'")
    if variable_name in globals():
        return str(globals()[variable_name])
    return None

def FINAL(name):
    return str(name)
'''
init_context = f"context = \"{prompt}\""

find_final_answer_string =  f"find_final_answer_string = \"\"\"{find_final_answer}\"\"\""
find_final_answer_code = f"""
match = re.search(final_var_pattern, find_final_answer_string, re.MULTILINE | re.DOTALL)
if match:
    variable_name = match.group(2).strip().strip('"').strip("'")
    if variable_name in globals():
        final_answer = FINAL_VAR(variable_name)
    else:
        final_answer = FINAL(variable_name)
    if final_answer is not None:
        final_answer = final_answer.strip()
    print(final_answer if final_answer else None)
"""

def output(result):
    if result.stderr:
        print(result.stderr, end="")
    elif result.stdout:
        print(result.stdout, end="")
    else:
        print("None", end="")

# create a new container if container_id is not provided, otherwise get the existing container
if container_id is None or container_id == "":
    sandbox = client.create()
    # run the initialization code in the Daytona environment
    _ = sandbox.code_interpreter.run_code(init_code)
    _ = sandbox.code_interpreter.run_code(init_context)
    print(sandbox.id,end="")
else:
    sandbox = client.get(container_id)

    if code:
        # execute the code in the Daytona environment
        result = sandbox.code_interpreter.run_code(code)
        output(result)
    elif find_final_answer:
        _ = sandbox.code_interpreter.run_code(find_final_answer_string)
        result = sandbox.code_interpreter.run_code(find_final_answer_code)
        output(result)
    else:
        pass

if delete:
    sandbox.delete()
    print(f"{sandbox.id}", end="")

