import os
import re

def rename_files():
    # Get all files in current directory
    files = os.listdir('.')
    
    # Skip hidden files and this script itself
    files = [f for f in files if not f.startswith('.') and f != 'rename_files.py']
    
    for filename in files:
        # Skip if not a png
        if not filename.endswith('.png'):
            continue
            
        # Split the name into parts
        name_parts = filename.split('.')
        
        # If we have a number in the middle (like 'radial.1.png'), remove it
        if len(name_parts) == 3:
            new_name = f"{name_parts[0]}.png"
            
            # Only rename if new name doesn't exist
            if not os.path.exists(new_name):
                os.rename(filename, new_name)
                print(f"Renamed {filename} to {new_name}")
            else:
                print(f"Skipped {filename} as {new_name} already exists")

if __name__ == "__main__":
    rename_files() 