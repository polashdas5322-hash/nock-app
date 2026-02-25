import os

# Define the root directory
ROOT_DIR = r"e:\Vive"
OUTPUT_FILE = os.path.join(ROOT_DIR, "all_native_code.txt")

# Define extensions and filenames to include (NO DART)
INCLUDE_EXTENSIONS = {
    # Android
    '.java', '.kt', '.xml', '.gradle', '.properties',
    # iOS
    '.h', '.m', '.swift', '.plist', '.xib', '.storyboard',
}

INCLUDE_FILENAMES = {
    'Podfile', 'Gemfile', 'AndroidManifest.xml', 'Info.plist', 'build.gradle'
}

# Define directories to exclude
EXCLUDE_DIRS = {
    'build', '.dart_tool', '.git', '.idea', '.vscode', '.gradle', 'Pods', 
    'Assets.xcassets', 'Runner.xcodeproj', 'Runner.xcworkspace',
    'ios/Flutter', 'android/app/build', 'node_modules',
    # Exclude lib entirely as it contains Dart code
    'lib' 
}

def is_excluded(path, root_dir):
    # Normalize path separators
    path = os.path.normpath(path)
    root_dir = os.path.normpath(root_dir)
    
    # Get relative path from root
    rel_path = os.path.relpath(path, root_dir)
    parts = rel_path.split(os.sep)
    
    # Check if any part of the path is in EXCLUDE_DIRS
    for part in parts:
        if part in EXCLUDE_DIRS or part.startswith('.'):
            return True
    return False

def main():
    print(f"Starting consolidation of NATIVE code in {ROOT_DIR}...")
    
    # Collect all files first to handle duplicates if any
    files_to_process = []
    
    for root, dirs, files in os.walk(ROOT_DIR):
        # Modify dirs in-place to skip excluded directories
        # We need to filter dirs based on their full relative path or name
        dirs[:] = [d for d in dirs if not is_excluded(os.path.join(root, d), ROOT_DIR)]
        
        for file in files:
            file_path = os.path.join(root, file)
            
            # Check for inclusion
            _, ext = os.path.splitext(file)
            if ext in INCLUDE_EXTENSIONS or file in INCLUDE_FILENAMES:
                 files_to_process.append(file_path)

    with open(OUTPUT_FILE, 'w', encoding='utf-8') as outfile:
        file_count = 0
        total_size = 0
        
        for file_path in files_to_process:
            rel_path = os.path.relpath(file_path, ROOT_DIR)
            
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

    print(f"\nSuccessfully combined {file_count} native files into {OUTPUT_FILE}")
    print(f"Total size: {total_size / (1024*1024):.2f} MB")

if __name__ == "__main__":
    main()
