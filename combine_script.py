import os

output_file = "all_project_code.txt"
root_dirs = ["lib", "android", "ios"]
extensions = [".dart", ".kt", ".java", ".xml", ".gradle", ".swift", ".h", ".m", ".plist", ".yaml", ".sh"]
exclude_dirs = ["build", ".dart_tool", ".idea", ".gradle", "Pods", "node_modules"] # Exclude large generated dirs

# Specific files to always include even if extensions don't match or in weird places
specific_includes = [
    "pubspec.yaml",
    "ios/Runner.xcodeproj/project.pbxproj",
    "ios/Podfile"
]

def should_process(file_path):
    # Check absolute path specific includes first to handle exact matches
    rel_path = os.path.relpath(file_path).replace("\\", "/") # Normalize separators for comparison
    if rel_path in specific_includes:
        return True
        
    # Check extensions
    _, ext = os.path.splitext(file_path)
    if ext not in extensions:
        return False
        
    # Check if inside excluded dir
    parts = file_path.split(os.sep)
    for part in parts:
        if part in exclude_dirs:
            return False
            
    return True

print(f"Starting to combine files into {output_file}...")

with open(output_file, "w", encoding="utf-8") as outfile:
    # 1. Process root directories recursively
    for root_dir in root_dirs:
        for root, dirs, files in os.walk(root_dir):
            # Prune excluded dirs in-place to avoid walking them
            dirs[:] = [d for d in dirs if d not in exclude_dirs]
            
            for file in files:
                file_path = os.path.join(root, file)
                if should_process(file_path):
                    try:
                        with open(file_path, "r", encoding="utf-8", errors="ignore") as infile:
                            content = infile.read()
                            outfile.write(f"\n\n{'='*80}\n")
                            outfile.write(f"FILE: {file_path}\n")
                            outfile.write(f"{'='*80}\n")
                            outfile.write(content)
                            print(f"Added: {file_path}")
                    except Exception as e:
                        print(f"Skipping {file_path}: {e}")

    # 2. Process specific root-level or special files that might not be in the recursive walk (like pubspec.yaml if not in root_dirs list)
    # The root_dirs list covers lib, android, ios. pubspec is in root.
    root_files = os.listdir(".")
    for file in root_files:
         if file == "all_project_code.txt": continue
         if file in specific_includes or (os.path.isfile(file) and should_process(file)):
            try:
                with open(file, "r", encoding="utf-8", errors="ignore") as infile:
                    content = infile.read()
                    outfile.write(f"\n\n{'='*80}\n")
                    outfile.write(f"FILE: {file}\n")
                    outfile.write(f"{'='*80}\n")
                    outfile.write(content)
                    print(f"Added root file: {file}")
            except Exception as e:
                print(f"Skipping root file {file}: {e}")

print("Done.")
