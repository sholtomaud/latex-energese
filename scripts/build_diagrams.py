import os
import subprocess
import json
import argparse

def build_diagram(json_path, output_dir):
    root_dir = os.getcwd()
    rel_json_path = os.path.relpath(os.path.abspath(json_path), start=os.path.abspath(output_dir))

    if not os.path.exists(output_dir):
        os.makedirs(output_dir)

    base_name = os.path.splitext(os.path.basename(json_path))[0]
    tex_path = os.path.join(output_dir, f"{base_name}.tex")
    png_path = os.path.join(output_dir, f"{base_name}.png")

    tex_content = f"""\\documentclass{{standalone}}
\\usepackage{{energese}}
\\begin{{document}}
\\renderEnergese{{{rel_json_path}}}
\\end{{document}}
"""
    with open(tex_path, "w") as f:
        f.write(tex_content)

    # Run lualatex
    env = os.environ.copy()
    # Add root to TEXINPUTS and LUAINPUTS
    env["TEXINPUTS"] = f".:{root_dir}:" + env.get("TEXINPUTS", "")
    env["LUAINPUTS"] = f".:{root_dir}:" + env.get("LUAINPUTS", "")

    subprocess.run(["lualatex", "-interaction=nonstopmode", f"{base_name}.tex"], cwd=output_dir, env=env, check=True)

    # Convert to PNG
    subprocess.run(["pdftoppm", "-png", "-singlefile", f"{base_name}.pdf", base_name], cwd=output_dir, check=True)

    print(f"Generated {png_path}")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input", help="JSON file or directory of JSON files")
    parser.add_argument("--output", default="output", help="Output directory")
    args = parser.parse_args()

    if os.path.isfile(args.input):
        build_diagram(args.input, args.output)
    elif os.path.isdir(args.input):
        for f in os.listdir(args.input):
            if f.endswith(".json"):
                build_diagram(os.path.join(args.input, f), args.output)

if __name__ == "__main__":
    main()
