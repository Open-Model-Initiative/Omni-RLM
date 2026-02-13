import re, sys, dill
dill.load_session("env.dill")
text = sys.argv[1]
final_var_pattern = r"^\s*FINAL(_VAR)?\((.*?)\)"
match = re.search(final_var_pattern, text, re.MULTILINE | re.DOTALL)
if match:
    variable_name = match.group(2).strip().strip('"').strip("'")
    if variable_name in globals():
        final_answer = FINAL_VAR(variable_name)
    else:
        final_answer = FINAL(variable_name)
    if final_answer is not None:
        final_answer = final_answer.strip()
    print(final_answer if final_answer else None)