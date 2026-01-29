import re, sys
def find_code_blocks(input):
        pattern = r"```repl\s*\n(.*?)```"
        result = []
        for match in re.finditer(pattern, input, re.DOTALL):
            code_content = match.group(1).strip()
            result.append(code_content)
        return result
input = sys.argv[1]
out = "\n".join(find_code_blocks(input))
final = re.search(r"FINAL(_VAR)?\((.*?)\)", input)
if final and "FINAL" not in out:
    out += "\n" + final.group(0)
print(out)