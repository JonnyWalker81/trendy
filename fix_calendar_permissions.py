#!/usr/bin/env python3
"""
Fix Calendar Permissions for Trendy App

This script adds the necessary calendar permission keys to the Xcode project file
to enable calendar access in the iOS app.
"""

import re
import shutil
from pathlib import Path

def add_calendar_permissions(project_file_path):
    """Add calendar permission keys to the Xcode project file."""
    
    # Create backup
    backup_path = project_file_path + '.backup'
    shutil.copy2(project_file_path, backup_path)
    print(f"✓ Created backup at: {backup_path}")
    
    # Read the project file
    with open(project_file_path, 'r') as f:
        content = f.read()
    
    # Define the permission strings
    calendar_usage_desc = 'This app needs access to your calendar to import events for tracking and visualization.'
    calendar_full_access_desc = 'This app needs full access to your calendar to import events for tracking and visualization.'
    
    # Define the keys to add
    calendar_keys = f'''				INFOPLIST_KEY_NSCalendarsUsageDescription = "{calendar_usage_desc}";
				INFOPLIST_KEY_NSCalendarsFullAccessUsageDescription = "{calendar_full_access_desc}";'''
    
    # Pattern to find where to insert (after UISupportedInterfaceOrientations_iPhone)
    pattern = r'(INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "[^"]+";)'
    
    # Counter for replacements
    replacements = 0
    
    # Function to perform replacement
    def replace_func(match):
        nonlocal replacements
        replacements += 1
        return match.group(1) + '\n' + calendar_keys
    
    # Replace in all build configurations
    modified_content = re.sub(pattern, replace_func, content)
    
    if replacements == 0:
        print("❌ Could not find the expected pattern in the project file.")
        print("   The project structure might be different than expected.")
        return False
    
    # Write the modified content back
    with open(project_file_path, 'w') as f:
        f.write(modified_content)
    
    print(f"✓ Added calendar permissions to {replacements} build configuration(s)")
    print("\n📝 Added keys:")
    print("   - NSCalendarsUsageDescription")
    print("   - NSCalendarsFullAccessUsageDescription")
    
    return True

def main():
    """Main function to fix calendar permissions."""
    print("🔧 Fixing Calendar Permissions for Trendy App\n")
    
    # Path to the project file
    project_path = Path("trendy.xcodeproj/project.pbxproj")
    
    if not project_path.exists():
        print(f"❌ Error: Could not find {project_path}")
        print("   Please run this script from the project root directory.")
        return 1
    
    # Add the permissions
    if add_calendar_permissions(str(project_path)):
        print("\n✅ Success! Calendar permissions have been added to the project.")
        print("\n📋 Next steps:")
        print("   1. Open trendy.xcodeproj in Xcode")
        print("   2. Clean the build folder (Cmd+Shift+K)")
        print("   3. Build and run the app")
        print("   4. The calendar permission dialog should now appear when importing events")
        print("\n💡 Tip: If you still don't see the permission dialog:")
        print("   - Delete the app from the simulator/device")
        print("   - Clean build folder again")
        print("   - Rebuild and reinstall the app")
        return 0
    else:
        print("\n❌ Failed to add calendar permissions.")
        print("   The backup file has been preserved.")
        return 1

if __name__ == "__main__":
    exit(main())