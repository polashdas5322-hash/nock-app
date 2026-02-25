import os

# Define the root directory
ROOT_DIR = r"e:\Vive"
OUTPUT_FILE = os.path.join(ROOT_DIR, "widget_deep_dive_bundle.txt")

# Specific files that define the Widget Experience
TARGET_FILES = [
    # --- FLUTTER (The Brain) ---
    r"lib\core\services\widget_update_service.dart",
    
    # --- iOS (The View & Interaction) ---
    r"ios\VibeWidget\VibeWidget.swift",
    r"ios\VibeWidget\PlayVibeIntent.swift",
    r"ios\Runner\Info.plist",
    r"ios\Runner\AudioManager.swift",
    
    # --- ANDROID (The View & Interaction) ---
    r"android\app\src\main\res\layout\nock_widget_layout.xml",
    r"android\app\src\main\res\layout\squad_widget_layout.xml",
    r"android\app\src\main\kotlin\com\nock\nock\NockWidgetProvider.kt",
    r"android\app\src\main\kotlin\com\nock\nock\NockAudioService.kt",
    r"android\app\src\main\AndroidManifest.xml",
    
    # --- CONFIG ---
    r"android\app\build.gradle",
    r"ios\Podfile"
]

def main():
    print(f"Creating specialized Widget Context Bundle in {OUTPUT_FILE}...")
    
    with open(OUTPUT_FILE, 'w', encoding='utf-8') as outfile:
        file_count = 0
        
        for rel_path in TARGET_FILES:
            file_path = os.path.join(ROOT_DIR, rel_path)
            
            if os.path.exists(file_path):
                try:
                    with open(file_path, 'r', encoding='utf-8', errors='ignore') as infile:
                        content = infile.read()
                        
                        outfile.write(f"\n{'='*80}\n")
                        outfile.write(f"FILE: {rel_path}\n")
                        outfile.write(f"{'='*80}\n\n")
                        outfile.write(content)
                        outfile.write("\n")
                        
                        file_count += 1
                        print(f"Added: {rel_path}")
                except Exception as e:
                    print(f"Error reading {rel_path}: {e}")
            else:
                print(f"WARNING: File not found: {rel_path}")

    print(f"\nSuccessfully bundled {file_count} critical widget files.")

if __name__ == "__main__":
    main()
