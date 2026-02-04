#!/usr/bin/env python3
"""
Factorio Mod Build and Release Script

This script automates the complete build and release process for Factorio mods:
1. Validates versions in info.json and changelog.txt
2. Builds the mod package
3. Creates a backup archive
4. Tests with Factorio
5. Creates git tag and GitHub release
"""

import json
import os
import re
import subprocess
import sys
import zipfile
from pathlib import Path
from typing import Tuple, Optional, List


class BuildError(Exception):
    """Custom exception for build errors"""
    pass


class SafeFileOps:
    """Wrapper for all file operations with safety checks"""
    
    def __init__(self, project_dir: Path, output_dir: Path):
        self.project_dir = project_dir.resolve()
        self.output_dir = output_dir.resolve()
        
    def _is_git_path(self, path: Path) -> bool:
        """Check if path is .git or inside .git directory"""
        try:
            resolved = path.resolve()
            git_dir = (self.project_dir / ".git").resolve()
            
            if resolved == git_dir:
                return True
            
            try:
                resolved.relative_to(git_dir)
                return True
            except ValueError:
                return False
        except:
            return False
            
    def _validate_path_in_project(self, path: Path, allow_git: bool = False) -> Path:
        """Validate path is within project directory and not .git"""
        resolved = path.resolve()
        
        # Must be within project directory
        try:
            resolved.relative_to(self.project_dir)
        except ValueError:
            raise BuildError(
                f"SAFETY: Path outside project directory!\n"
                f"  Path: {resolved}\n"
                f"  Project: {self.project_dir}"
            )
        
        # Check .git protection
        if not allow_git and self._is_git_path(resolved):
            raise BuildError(
                f"SAFETY: Cannot modify .git directory!\n"
                f"  Path: {resolved}"
            )
            
        return resolved
        
    def _validate_path_in_output(self, path: Path) -> Path:
        """Validate path is within output directory"""
        resolved = path.resolve()
        
        # Must be within output directory
        try:
            resolved.relative_to(self.output_dir)
        except ValueError:
            raise BuildError(
                f"SAFETY: Path outside output directory!\n"
                f"  Path: {resolved}\n"
                f"  Output: {self.output_dir}"
            )
        
        # Must be direct child (not in subdirectory)
        if resolved.parent != self.output_dir:
            raise BuildError(
                f"SAFETY: Path not direct child of output directory!\n"
                f"  Path: {resolved}"
            )
            
        return resolved
        
    def safe_unlink(self, path: Path):
        """Safely delete a file"""
        validated = self._validate_path_in_project(path, allow_git=False)
        if not validated.is_file():
            raise BuildError(f"SAFETY: Not a file: {validated}")
        validated.unlink()
        
    def safe_rmtree(self, path: Path):
        """Safely delete a directory tree"""
        import shutil
        validated = self._validate_path_in_project(path, allow_git=False)
        if not validated.is_dir():
            raise BuildError(f"SAFETY: Not a directory: {validated}")
        shutil.rmtree(validated)
        
    def safe_write(self, path: Path, content: str, mode: str = 'w'):
        """Safely write to a file"""
        # Resolve path first
        resolved = path.resolve()
        
        # Check if in project dir
        try:
            resolved.relative_to(self.project_dir)
            validated = self._validate_path_in_project(path, allow_git=False)
        except ValueError:
            # Not in project dir, check if in output dir
            try:
                resolved.relative_to(self.output_dir)
                validated = self._validate_path_in_output(path)
            except ValueError:
                raise BuildError(f"SAFETY: Path not in allowed locations: {resolved}")
            
        with open(validated, mode) as f:
            f.write(content)
            
    def safe_mkdir(self, path: Path, parents: bool = False, exist_ok: bool = False):
        """Safely create a directory"""
        validated = self._validate_path_in_project(path, allow_git=False)
        validated.mkdir(parents=parents, exist_ok=exist_ok)


class RemoteCommandWrapper:
    """Wrapper for all git and gh commands - prints instead of executing"""
    
    def __init__(self, project_dir: Path):
        self.project_dir = project_dir
        self.commands = []
        
    def git_command(self, args: List[str], description: str = ""):
        """Queue a git command to be printed"""
        self.commands.append({
            'type': 'git',
            'args': args,
            'description': description
        })
        
    def gh_command(self, args: List[str], description: str = ""):
        """Queue a gh command to be printed"""
        self.commands.append({
            'type': 'gh',
            'args': args,
            'description': description
        })
        
    def print_all_commands(self):
        """Print all queued commands"""
        if not self.commands:
            return
            
        print("\n" + "="*70)
        print("REMOTE COMMANDS TO RUN MANUALLY:")
        print("="*70)
        print(f"\ncd {self.project_dir}\n")
        
        for cmd in self.commands:
            if cmd['description']:
                print(f"# {cmd['description']}")
            
            cmd_str = ' '.join([cmd['type']] + cmd['args'])
            print(f"{cmd_str}")
            print()
        
        print("="*70)


class ModBuilder:
    def __init__(self, factorio_path: str = "/path/to/factorio"):
        # Determine project directory (script is in projectdir/scripts)
        self.script_dir = Path(__file__).parent.resolve()
        self.project_dir = self.script_dir.parent
        self.tmp_dir = self.project_dir / "tmp"
        self.output_dir = self.project_dir.parent
        
        self.factorio_path = Path(factorio_path)
        
        self.version = None
        self.previous_version = None
        self.mod_name = None
        self.zip_name = None
        self.backup_name = None
        
        # Initialize safety wrappers
        self.file_ops = SafeFileOps(self.project_dir, self.output_dir)
        self.remote_cmds = RemoteCommandWrapper(self.project_dir)
        
        # Validate paths are safe
        self._validate_paths()
        
    def _validate_paths(self):
        """Ensure all paths are within safe boundaries"""
        # Project dir must be resolved and absolute
        if not self.project_dir.is_absolute():
            raise BuildError(f"Project directory path is not absolute: {self.project_dir}")
            
        # Output dir must be exactly one level up from project dir
        expected_output = self.project_dir.parent
        if self.output_dir.resolve() != expected_output.resolve():
            raise BuildError(
                f"Output directory validation failed!\n"
                f"  Expected: {expected_output}\n"
                f"  Got:      {self.output_dir}"
            )
            
        # Ensure we're not at filesystem root (extra safety)
        if self.project_dir == self.project_dir.parent:
            raise BuildError("Project directory cannot be filesystem root!")
        
    def log(self, message: str, level: str = "INFO"):
        """Print a formatted log message"""
        print(f"[{level}] {message}")
        
    def validate_version_format(self, version: str) -> bool:
        """Validate version is in vX.Y.Z format"""
        pattern = r'^v\d+\.\d+\.\d+$'
        return bool(re.match(pattern, version))
        
    def extract_version_from_info_json(self) -> str:
        """Extract version from info.json"""
        info_path = self.project_dir / "info.json"
        if not info_path.exists():
            raise BuildError(f"info.json not found at {info_path}")
            
        with open(info_path, 'r') as f:
            info = json.load(f)
            
        if 'version' not in info:
            raise BuildError("'version' field not found in info.json")
        if 'name' not in info:
            raise BuildError("'name' field not found in info.json")
            
        self.mod_name = info['name']
        version = info['version']
        
        # Add 'v' prefix if not present
        if not version.startswith('v'):
            version = 'v' + version
            
        return version
        
    def extract_versions_from_changelog(self) -> Tuple[str, Optional[str]]:
        """Extract current and previous version from changelog.txt"""
        changelog_path = self.project_dir / "changelog.txt"
        if not changelog_path.exists():
            raise BuildError(f"changelog.txt not found at {changelog_path}")
            
        with open(changelog_path, 'r') as f:
            content = f.read()
            
        # Find all version entries
        version_pattern = r'Version:\s*(\d+\.\d+\.\d+)'
        matches = re.findall(version_pattern, content)
        
        if not matches:
            raise BuildError("No version found in changelog.txt")
            
        current = 'v' + matches[0]
        previous = 'v' + matches[1] if len(matches) > 1 else None
        
        return current, previous
        
    def validate_versions(self):
        """Validate versions from info.json and changelog.txt match"""
        self.log("Validating versions...")
        
        info_version = self.extract_version_from_info_json()
        changelog_version, self.previous_version = self.extract_versions_from_changelog()
        
        # Validate format
        if not self.validate_version_format(info_version):
            raise BuildError(f"Version in info.json '{info_version}' is not in vX.Y.Z format")
            
        if not self.validate_version_format(changelog_version):
            raise BuildError(f"Version in changelog.txt '{changelog_version}' is not in vX.Y.Z format")
            
        # Check if they match
        if info_version != changelog_version:
            raise BuildError(
                f"Version mismatch!\n"
                f"  info.json:      {info_version}\n"
                f"  changelog.txt:  {changelog_version}"
            )
            
        # Validate previous version format if it exists
        if self.previous_version and not self.validate_version_format(self.previous_version):
            raise BuildError(f"Previous version in changelog.txt '{self.previous_version}' is not in vX.Y.Z format")
            
        self.version = info_version
        self.log(f"Current version: {self.version}")
        if self.previous_version:
            self.log(f"Previous version: {self.previous_version}")
        else:
            self.log("No previous version found (first release?)")
            
    def build_zip_package(self):
        """Build the mod zip package"""
        self.log("Building mod package...")
        
        # Remove 'v' prefix for filename
        version_number = self.version[1:] if self.version.startswith('v') else self.version
        version_name = f"{self.mod_name}_{version_number}"
        self.zip_name = f"{version_name}.zip"
        zip_path = self.output_dir / self.zip_name
        
        # Validate output path through wrapper
        zip_path = self.file_ops._validate_path_in_output(zip_path)
        
        self.log(f"Creating {zip_path}")
        
        with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zout:
            for root, dirs, files in os.walk(self.project_dir):
                # Skip .git directory
                if '.git' in dirs:
                    dirs.remove('.git')
                # Skip scripts directory
                if 'scripts' in dirs:
                    dirs.remove('scripts')
                # Skip tmp directory
                if 'tmp' in dirs:
                    dirs.remove('tmp')
                    
                for file in files:
                    # Skip existing zip files
                    if file.endswith('.zip') or file.endswith('.7z'):
                        continue
                    # Skip backup files
                    if file.endswith('~'):
                        continue
                        
                    full_path = Path(root) / file
                    # Calculate relative path from project directory
                    rel_path = full_path.relative_to(self.project_dir)
                    # Archive path includes version name as root
                    archive_path = Path(version_name) / rel_path
                    
                    self.log(f"  Adding: {rel_path}", level="DEBUG")
                    zout.write(full_path, arcname=str(archive_path))
                    
        self.log(f"Package created: {zip_path}")
        
    def create_backup(self):
        """Create a 7z backup of the project directory"""
        self.log("Creating backup archive...")
        
        self.backup_name = f"{self.mod_name}_{self.version}_backup.7z"
        backup_path = self.output_dir / self.backup_name
        
        # Validate output path through wrapper
        backup_path = self.file_ops._validate_path_in_output(backup_path)
        
        # Check if 7z is available
        try:
            subprocess.run(['7z', '--help'], capture_output=True, check=True)
        except (subprocess.CalledProcessError, FileNotFoundError):
            self.log("7z not found, trying 7za...", level="WARN")
            try:
                subprocess.run(['7za', '--help'], capture_output=True, check=True)
                seven_z_cmd = '7za'
            except (subprocess.CalledProcessError, FileNotFoundError):
                raise BuildError("Neither 7z nor 7za found. Please install p7zip-full")
        else:
            seven_z_cmd = '7z'
        
        # Create backup excluding .git - use explicit project directory path
        # Use '.' to ensure we only archive current directory contents
        cmd = [
            seven_z_cmd, 'a',
            str(backup_path),
            '.',
            '-xr!.git',
            '-xr!*.zip',
            '-xr!*.7z',
        ]
        
        self.log(f"Creating {backup_path}")
        # Run from project directory to ensure only project contents are archived
        result = subprocess.run(cmd, capture_output=True, text=True, cwd=str(self.project_dir))
        
        if result.returncode != 0:
            raise BuildError(f"Failed to create backup: {result.stderr}")
            
        self.log(f"Backup created: {backup_path}")
        
    def clean_project_directory(self):
        """Remove everything from project directory except .git"""
        self.log("Cleaning project directory (keeping .git)...")
        
        # Safety check: ensure we're only deleting within project directory
        for item in self.project_dir.iterdir():
            if item.name == '.git':
                continue
            
            # Use safe wrappers for all deletions
            if item.is_file():
                self.log(f"  Removing file: {item.name}", level="DEBUG")
                self.file_ops.safe_unlink(item)
            elif item.is_dir():
                self.log(f"  Removing directory: {item.name}", level="DEBUG")
                self.file_ops.safe_rmtree(item)
                
        self.log("Project directory cleaned")
        
    def run_factorio(self):
        """Run Factorio for testing"""
        self.log("Starting Factorio for testing...")
        
        if not self.factorio_path.exists():
            raise BuildError(f"Factorio not found at {self.factorio_path}")
            
        self.log(f"Running: {self.factorio_path}")
        self.log("Please test the mod and close Factorio when done.")
        
        try:
            subprocess.run([str(self.factorio_path)], check=True)
        except subprocess.CalledProcessError as e:
            raise BuildError(f"Factorio exited with error: {e}")
            
        self.log("Factorio closed")
        
    def confirm_proceed(self) -> bool:
        """Ask user for confirmation to proceed with release"""
        self.log("\n" + "="*70)
        self.log("Ready to create release:")
        self.log(f"  Version: {self.version}")
        self.log(f"  Package: {self.zip_name}")
        if self.previous_version:
            self.log(f"  Previous: {self.previous_version}")
        self.log("="*70)
        
        response = input("\nProceed with git tag and GitHub release? [y/N]: ").strip().lower()
        return response in ['y', 'yes']
        
    def create_git_tag(self):
        """Prepare git tag commands - DOES NOT EXECUTE"""
        self.log(f"Preparing git tag {self.version}...")
        
        # Check if tag already exists
        result = subprocess.run(
            ['git', 'tag', '-l', self.version],
            capture_output=True,
            text=True,
            cwd=self.project_dir
        )
        
        if result.stdout.strip():
            raise BuildError(f"Git tag {self.version} already exists!")
        
        # Queue commands through wrapper (will be printed, not executed)
        self.remote_cmds.git_command(
            ['tag', '-a', self.version, '-m', f'Release {self.version}'],
            description=f"Create tag {self.version}"
        )
        self.remote_cmds.git_command(
            ['push', 'origin', self.version],
            description=f"Push tag to remote"
        )
        
        self.log(f"Git tag commands prepared")
        
    def extract_changelog_for_release(self) -> str:
        """Extract changelog entry for current version"""
        self.log("Extracting changelog for release notes...")
        
        # Create tmp directory if it doesn't exist using safe wrapper
        self.file_ops.safe_mkdir(self.tmp_dir, exist_ok=True)
        
        changelog_path = self.project_dir / "changelog.txt"
        changes_path = self.tmp_dir / "changes.txt"
        
        with open(changelog_path, 'r') as f:
            lines = f.readlines()
            
        # Skip first 3 lines
        lines = lines[3:]
        
        # Find first ---- line and take everything before it
        changes = []
        for line in lines:
            if line.strip().startswith('----'):
                break
            changes.append(line)
            
        # Remove two spaces at start of lines
        changes = [line[2:] if line.startswith('  ') else line for line in changes]
        
        # Add linebreak before lines starting with non-space (except first line)
        result = []
        for i, line in enumerate(changes):
            if i > 0 and line and not line[0].isspace():
                result.append('\n')
            result.append(line)
            
        changelog_text = ''.join(result).strip()
        
        # Save to file using safe wrapper
        self.file_ops.safe_write(changes_path, changelog_text)
        
        self.log(f"Changelog extracted to {changes_path}")
        return changelog_text
        
    def verify_previous_tag(self):
        """Verify that previous tag exists if we have a previous version"""
        if not self.previous_version:
            return
            
        self.log(f"Verifying previous tag {self.previous_version} exists...")
        
        result = subprocess.run(
            ['git', 'tag', '-l', self.previous_version],
            capture_output=True,
            text=True,
            cwd=self.project_dir
        )
        
        if not result.stdout.strip():
            raise BuildError(
                f"Previous tag {self.previous_version} not found in git!\n"
                f"Expected tag from previous version in changelog."
            )
            
        self.log(f"Previous tag {self.previous_version} verified")
        
    def create_github_release(self):
        """Prepare GitHub release command - DOES NOT EXECUTE"""
        self.log("Preparing GitHub release...")
        
        # Check if gh is available
        try:
            subprocess.run(['gh', '--version'], capture_output=True, check=True)
        except (subprocess.CalledProcessError, FileNotFoundError):
            raise BuildError("GitHub CLI (gh) not found. Please install it first.")
            
        changelog_text = self.extract_changelog_for_release()
        changes_path = self.tmp_dir / "changes.txt"
        zip_path = self.output_dir / self.zip_name
        
        # Validate that zip file exists
        if not zip_path.exists():
            raise BuildError(f"Package file not found: {zip_path}")
        
        # Queue command through wrapper (will be printed, not executed)
        self.remote_cmds.gh_command(
            [
                'release', 'create',
                self.version,
                str(zip_path),
                '-t', f'Version {self.version}',
                '-F', str(changes_path)
            ],
            description=f"Create GitHub release for {self.version}"
        )
        
        self.log(f"Changelog notes saved to: {changes_path}")
        self.log("GitHub release command prepared")
        self.log("DO NOT delete changes.txt until after running the command!", level="WARN")
        
    def run(self, skip_factorio: bool = False, skip_clean: bool = False):
        """Run the complete build and release process"""
        try:
            # Step 1: Validate versions
            self.validate_versions()
            
            # Step 2: Build package
            self.build_zip_package()
            
            # Step 3: Create backup
            self.create_backup()
            
            # Step 4: Clean project directory (optional)
            if not skip_clean:
                self.clean_project_directory()
            else:
                self.log("Skipping project directory cleanup")
            
            # Step 5: Run Factorio (optional)
            if not skip_factorio:
                self.run_factorio()
            else:
                self.log("Skipping Factorio test run")
            
            # Step 6: Confirm before proceeding
            if not self.confirm_proceed():
                self.log("Release cancelled by user", level="WARN")
                return
                
            # Step 7: Verify previous tag
            self.verify_previous_tag()
            
            # Step 8: Prepare git tag commands
            self.create_git_tag()
            
            # Step 9: Prepare GitHub release command
            self.create_github_release()
            
            # Step 10: Print all remote commands
            self.remote_cmds.print_all_commands()
            
            self.log("\n" + "="*70)
            self.log("BUILD COMPLETE!", level="SUCCESS")
            self.log(f"  Version: {self.version}")
            self.log(f"  Package: {self.output_dir / self.zip_name}")
            self.log(f"  Backup:  {self.output_dir / self.backup_name}")
            self.log("")
            self.log("Next steps (MANUAL):")
            self.log("  1. Run the git tag commands printed above")
            self.log("  2. Run the GitHub release command printed above")
            self.log("  3. Verify the release on GitHub")
            self.log("="*70)
            
        except BuildError as e:
            self.log(f"ERROR: {e}", level="ERROR")
            sys.exit(1)
        except KeyboardInterrupt:
            self.log("\nBuild cancelled by user", level="WARN")
            sys.exit(1)
        except Exception as e:
            self.log(f"UNEXPECTED ERROR: {e}", level="ERROR")
            import traceback
            traceback.print_exc()
            sys.exit(1)


def main():
    import argparse
    
    parser = argparse.ArgumentParser(
        description="Build and release Factorio mod",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s
  %(prog)s --factorio-path /usr/games/factorio
  %(prog)s --skip-factorio --skip-clean
        """
    )
    
    parser.add_argument(
        '--factorio-path',
        default='/path/to/factorio',
        help='Path to Factorio executable (default: /path/to/factorio)'
    )
    parser.add_argument(
        '--skip-factorio',
        action='store_true',
        help='Skip running Factorio for testing'
    )
    parser.add_argument(
        '--skip-clean',
        action='store_true',
        help='Skip cleaning project directory'
    )
    
    args = parser.parse_args()
    
    builder = ModBuilder(factorio_path=args.factorio_path)
    builder.run(skip_factorio=args.skip_factorio, skip_clean=args.skip_clean)


if __name__ == '__main__':
    main()