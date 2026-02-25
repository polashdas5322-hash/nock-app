import os

# Define the root directory
ROOT_DIR = r"e:\Vive"
OUTPUT_FILE = os.path.join(ROOT_DIR, "all_project_code.txt")

# Define extensions and filenames to include
INCLUDE_EXTENSIONS = {
    # Dart
    '.dart', 
    '.yaml', 
    # Android
    '.java', '.kt', '.xml', '.gradle', '.properties',
    # iOS
    '.h', '.m', '.swift', '.plist', '.xib', '.storyboard',
    # General
    '.json', '.md'
}

INCLUDE_FILENAMES = {
    'Podfile', 'Gemfile', 'AndroidManifest.xml', 'Info.plist', 'pubspec.yaml', 'build.gradle'
}

# Define directories to exclude
EXCLUDE_DIRS = {
    'build', '.dart_tool', '.git', '.idea', '.vscode', '.gradle', 'Pods', 
    'Assets.xcassets', 'Runner.xcodeproj', 'Runner.xcworkspace',
    'ios/Flutter', 'android/app/build', 'node_modules'
}

def is_excluded(path):
    parts = path.split(os.sep)
    for part in parts:
        if part in EXCLUDE_DIRS or part.startswith('.'):
            return True
    return False

def main():
    print(f"Starting consolidation of code in {ROOT_DIR}...")
    
    with open(OUTPUT_FILE, 'w', encoding='utf-8') as outfile:
        file_count = 0
        total_size = 0
        
        for root, dirs, files in os.walk(ROOT_DIR):
            # Modify dirs in-place to skip excluded directories
            dirs[:] = [d for d in dirs if not is_excluded(os.path.join(root, d)) and not d.startswith('.')]
            
            for file in files:
                file_path = os.path.join(root, file)
                rel_path = os.path.relpath(file_path, ROOT_DIR)
                
                # Check for exclusion
                if is_excluded(file_path):
                    continue
                
                # Check for inclusion
                _, ext = os.path.splitext(file)
                if ext in INCLUDE_EXTENSIONS or file in INCLUDE_FILENAMES:
                    try:
                        # Skip large binary files or generated files if any slip through
                        if os.path.getsize(file_path) > 1024 * 1024: # Skip > 1MB
                            print(f"Skipping large file: {rel_path}")
                            continue

                        with open(file_path, 'r', encoding='utf-8', errors='ignore') as infile:
                            content = infile.read()
                            
                            outfile.write(f"\n{'='*80}\n")
                            outfile.write(f"FILE: {rel_path}\n")
                            outfile.write(f"{'='*80}\n\n")
                            outfile.write(content)
                            outfile.write("\n")
                            
                            file_count += 1
                            total_size += len(content)
                            print(f"Added: {rel_path}")
                            
                    except Exception as e:
                        print(f"Error reading {rel_path}: {e}")

    print(f"\nSuccessfully combined {file_count} files into {OUTPUT_FILE}")
    print(f"Total size: {total_size / (1024*1024):.2f} MB")

if __name__ == "__main__":
    main()
