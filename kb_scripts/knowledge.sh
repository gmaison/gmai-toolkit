#!/bin/zsh

# Enable zsh features
setopt EXTENDED_GLOB
setopt NULL_GLOB
setopt PIPE_FAIL
setopt ERR_EXIT
setopt NO_UNSET

# Colors and formatting
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    printf "%b→ %b%s%b\n" "$BLUE" "$NC" "$1" "$NC"
}

log_success() {
    printf "%b✓ %b%s%b\n" "$GREEN" "$NC" "$1" "$NC"
}

log_error() {
    printf "%b✗ %b%s%b\n" "$RED" "$NC" "$1" "$NC" >&2
}

log_warning() {
    printf "%b! %b%s%b\n" "$YELLOW" "$NC" "$1" "$NC"
}

print_header() {
    printf "\n%b%s%b\n" "$BOLD" "$1" "$NC"
}

# Default configuration
DEFAULT_FILE_PERMS=644
DEFAULT_DIR_PERMS=755
DEFAULT_PROCESS_MODE="full"

# Script initialization
# Set up readonly variables
typeset -r SCRIPT_NAME=${0:t}
typeset -r SCRIPT_DIR=${0:h}
typeset -r PROJECT_ROOT=${$(git rev-parse --show-toplevel 2>/dev/null):-.}

# Initialize default configuration
KB_FILENAME="knowledge.md"
KB_DIRNAME="knowledge_base"
KB_HEADER_FILE=".kbheader"
IGNORE_FILE=".kbignore"
INCLUDE_FILE=".kbinclude"
DOC_DIR="documentation"
CODEBASE_DIR="apps"

# Ensure we're in the right directory
cd "$SCRIPT_DIR" || {
    log_error "Failed to change to script directory"
    exit 1
}

# Set up configurable variables with defaults
FILE_PERMS=${FILE_PERMS:-$DEFAULT_FILE_PERMS}
DIR_PERMS=${DIR_PERMS:-$DEFAULT_DIR_PERMS}
PROCESS_MODE=${PROCESS_MODE:-$DEFAULT_PROCESS_MODE}

# Validate permissions are valid octal numbers
if ! [[ "$FILE_PERMS" =~ ^[0-7]{3}$ ]]; then
    log_error "Invalid file permissions: $FILE_PERMS"
    exit 1
fi

if ! [[ "$DIR_PERMS" =~ ^[0-7]{3}$ ]]; then
    log_error "Invalid directory permissions: $DIR_PERMS"
    exit 1
fi

# Validate critical paths
if [[ ! -d $SCRIPT_DIR || ! -d $PROJECT_ROOT ]]; then
    log_error "Invalid script or project directory"
    exit 1
fi

# Error handling
trap 'error_handler $?' EXIT

error_handler() {
    local exit_code=$1
    if (( exit_code != 0 )); then
        # Don't exit if we're already in error handling
        if (( ${HANDLING_ERROR:-0} == 0 )); then
            HANDLING_ERROR=1
            log_error "Script failed with exit code: $exit_code"
            return $exit_code
        fi
    fi
    # Reset error handling flag on successful completion
    HANDLING_ERROR=0
    return 0
}

# Command line argument processing
parse_args() {

    # Initialize default values
    VERBOSE=false
    KB_DIRNAME="knowledge_base"
    PROCESS_MODE="documentation"
    
    # Parse command line options
    while getopts "hvd:m:" opt; do
        case $opt in
            h)
                show_usage
                exit 0
                ;;
            v)
                VERBOSE=true
                ;;
            d)
                if [ -z "$OPTARG" ]; then
                    log_error "Directory argument is empty"
                    show_usage
                    return 1
                fi
                KB_DIRNAME="$OPTARG"
                ;;
            m)
                # Split modes by comma
                local modes=(${(s:,:)OPTARG})
                local valid_modes=(documentation codebase cursor_rules windsurf_rules full)
                local invalid_mode=false
                
                # Validate each mode
                for mode in $modes; do
                    if [[ ! " ${valid_modes[@]} " =~ " $mode " ]]; then
                        log_error "Invalid mode: $mode"
                        invalid_mode=true
                    fi
                done
                
                if [ "$invalid_mode" = true ]; then
                    show_usage
                    return 1
                fi
                
                PROCESS_MODE="$OPTARG"
                ;;
            ?)
                show_usage
                return 1
                ;;
        esac
    done
    
    # Export variables for use in other functions
    typeset -gr VERBOSE
    typeset -gr KB_DIRNAME
    typeset -gr PROCESS_MODE
    
    return 0
}

# Show usage information
show_usage() {
    cat << EOF
Usage: $SCRIPT_NAME [-h] [-v] [-d dir] [-m mode1,mode2,...]

Generate knowledge base documentation

Options:
  -h        Show this help message
  -v        Enable verbose output
  -d dir    Set knowledge base directory
  -m modes  Set processing modes (comma-separated)
            Available modes:
              documentation:   Generate knowledge base of documentation
              codebase:       Generate knowledge base of monorepo source code
              cursor_rules:   Generate knowledge base of cursor rules
              windsurf_rules: Generate knowledge base of windsurf rules
              full:           Generate complete knowledge base
            Example: -m documentation,codebase
EOF
}

# Parse command line arguments
parse_args "$@" || exit 1

# Initialize and validate configuration
init_config() {
    typeset -gA CONFIG

    # Set default configuration
    CONFIG[kb_filename]="${KB_FILENAME:-knowledge.md}"
    CONFIG[KB_DIRNAME]="${KB_DIRNAME:-knowledge_base}"
    CONFIG[ignore_file]="${IGNORE_FILE:-.kbignore}"
    CONFIG[header_file]="${HEADER_FILE:-.kbheader}"
    CONFIG[include_file]="${INCLUDE_FILE:-.kbinclude}"
    CONFIG[doc_dir]="${DOC_DIR:-documentation}"
    CONFIG[file_perms]="${FILE_PERMS:-$DEFAULT_FILE_PERMS}"
    CONFIG[dir_perms]="${DIR_PERMS:-$DEFAULT_DIR_PERMS}"
    CONFIG[codebase_dir]="${CODEBASE_DIR:-apps}"
    
    # Validate configuration values
    if ! [[ "${CONFIG[kb_filename]}" =~ \.(md|mdx)$ ]]; then
        log_error "Invalid knowledge base filename extension: ${CONFIG[kb_filename]}"
        return 1
    fi
    
    if [[ "${CONFIG[KB_DIRNAME]}" =~ ^[[:space:]]*$ ]]; then
        log_error "Knowledge base directory cannot be empty"
        return 1
    fi
    
    if ! [[ "${CONFIG[file_perms]}" =~ ^[0-7]{3}$ ]]; then
        log_error "Invalid file permissions: ${CONFIG[file_perms]}"
        return 1
    fi
    
    if ! [[ "${CONFIG[dir_perms]}" =~ ^[0-7]{3}$ ]]; then
        log_error "Invalid directory permissions: ${CONFIG[dir_perms]}"
        return 1
    fi
    
    # Initialize paths
    local key
    for key in ${(k)CONFIG}; do
        if [[ -z ${CONFIG[$key]} ]]; then
            log_error "Empty configuration value for $key"
            return 1
        fi
    done
    
    # Initialize derived paths
    init_paths    

    return 0
}

# Initialize derived paths
init_paths() {

    # Set readonly paths
    typeset -gr KB_DIR="$PROJECT_ROOT/${CONFIG[KB_DIRNAME]}"
    typeset -gr OUTPUT_FILE="$KB_DIR/${CONFIG[kb_filename]}"
    
    typeset -gr HEADER_FILE="$PROJECT_ROOT/${CONFIG[header_file]}"
    typeset -gr INCLUDE_FILE="$PROJECT_ROOT/${CONFIG[include_file]}"
    typeset -gr IGNORE_FILE="$PROJECT_ROOT/${CONFIG[ignore_file]}"
    typeset -gr DOC_DIR="$PROJECT_ROOT/${CONFIG[doc_dir]}"
    typeset -gr CODEBASE_DIR="$PROJECT_ROOT/${CONFIG[codebase_dir]}"
    
    # Validate critical paths
    if [ ! -d "$PROJECT_ROOT" ]; then
        log_error "Invalid project root directory: $PROJECT_ROOT"
        return 1
    fi
    


    return 0
}

# Initialize configuration
init_config || exit 1

# Statistics management functions
init_stats() {
    declare -gA STATS=(
        [processed_files]=0
        [skipped_files]=0
        [errors]=0
    )
}

# Update statistics
update_stats() {
    local stat_name=${1:?"Stat name required"}
    local increment=${2:-1}
    
    # Validate increment is a number
    if ! [[ "$increment" =~ ^[0-9]+$ ]]; then
        log_error "Invalid increment value: $increment"
        return 1
    fi
    
    if [ -n "${STATS[$stat_name]+x}" ]; then
        # Prevent integer overflow
        if [ "$((STATS[$stat_name] + increment))" -lt 0 ]; then
            log_error "Statistics overflow for $stat_name"
            return 1
        fi
        ((STATS[$stat_name]+=increment))
    else
        log_warning "Unknown statistic: $stat_name"
        return 1
    fi
}

# Print statistics
print_stats() {
    print_header "Statistics"
    printf "Processed files: %d\n" "${STATS[processed_files]}"
    printf "Skipped files: %d\n" "${STATS[skipped_files]}"
    printf "Errors: %d\n" "${STATS[errors]}"
}

# Initialize statistics
init_stats

# Colors and formatting
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Functions
log_info() {
    printf "%b→ %b%s%b\n" "$BLUE" "$NC" "$1" "$NC"
}

log_success() {
    printf "%b✓ %b%s%b\n" "$GREEN" "$NC" "$1" "$NC"
}

log_error() {
    printf "%b✗ %b%s%b\n" "$RED" "$NC" "$1" "$NC" >&2
    # Only exit if we're not in error handling
    if (( ${HANDLING_ERROR:-0} == 0 )); then
        return 1
    fi
}

log_warning() {
    printf "%b! %b%s%b\n" "$YELLOW" "$NC" "$1" "$NC"
}

print_header() {
    printf "\n%b%s%b\n\n" "$BOLD" "$1" "$NC"
}

get_file_extension() {
    local filename=$1
    local ext="${filename##*.}"
    if [[ $ext == $filename ]]; then
        print -n "txt"
    else
        print -n "$ext"
    fi
}

should_exclude() {
    local file_path="$1"
    
    # If ignore file doesn't exist or isn't readable, nothing is excluded
    if [[ ! -r "$IGNORE_FILE" ]]; then
        $VERBOSE && log_warning "Ignore file not found or not readable: $IGNORE_FILE"
        return 1
    fi
    
    # Cache the ignore patterns for better performance
    if [[ -z ${IGNORE_PATTERNS+1} ]]; then
        declare -ga IGNORE_PATTERNS=()
        while IFS= read -r pattern; do
            # Skip empty lines and comments
            if [[ -n "$pattern" && ! "$pattern" =~ ^#.*$ ]]; then
                # Trim whitespace and convert to glob pattern
                pattern=${${pattern##[[:space:]]#}%%[[:space:]]#}
                pattern=${pattern%/}  # Remove trailing slash
                IGNORE_PATTERNS+=("*/$pattern*")
            fi
        done < "$IGNORE_FILE"
        $VERBOSE && log_info "Loaded ${#IGNORE_PATTERNS[@]} ignore patterns"
    fi
    
    # Check against cached patterns
    for pattern in "${IGNORE_PATTERNS[@]}"; do
        if [[ "$file_path" = ${~pattern} ]]; then
            return 0
        fi
    done
    
    return 1
}

process_kb_init() {
    local exit_code=0
    local dir_perms=755
    local file_perms=644
    
    # Create and secure knowledge base directory
    if [[ ! -d "$KB_DIR" ]]; then
        if ! mkdir -p "$KB_DIR" 2>/dev/null; then
            log_error "Failed to create knowledge base directory: $KB_DIR"
            return 1
        fi
        chmod $dir_perms "$KB_DIR"
        $VERBOSE && log_success "Created knowledge base directory with secure permissions"
    fi
    
    # Initialize required files with secure permissions
    init_file "$HEADER_FILE" "header" "# Project Specifications \"Knowledge Base\"\n\nThis project specifications will help you understand the project architecture and features.\n\nIt might not be up to date, always refer to code as source of truth.\n" || exit_code=$?
        
    init_file "$IGNORE_FILE" "ignore" "# Ignore files for knowledge base generation\n# Example:\n# node_modules/\n# *.test.js\n# dist/\n# .git/\n" || exit_code=$?

    init_file "$INCLUDE_FILE" "include" "# Files to include in the knowledge base\n# Example:\n# apps/backend/package.json\n" || exit_code=$?

    return $exit_code
}

# Helper function to initialize files with proper permissions
init_file() {
    local file_path=${1:?"File path required"}
    local file_type=${2:?"File type required"}
    local content=${3:?"Content required"}
    local file_perms=${FILE_PERMS:-644}
    local dir_perms=${DIR_PERMS:-755}
    
    # Ensure parent directory exists with proper permissions
    local dir_path
    dir_path=$(dirname "$file_path") || {
        log_error "Failed to get directory path for: $file_path"
        return 1
    }
    
    if [[ ! -d $dir_path ]]; then
        if ! mkdir -p "$dir_path" 2>/dev/null; then
            log_error "Failed to create directory: $dir_path"
            return 1
        fi
        chmod "$dir_perms" "$dir_path" || {
            log_error "Failed to set directory permissions: $dir_path"
            return 1
        }
    fi
    
    if [[ ! -f $file_path ]]; then
        # Create file with secure permissions
        if ! printf "%b" "$content" > "$file_path" 2>/dev/null; then
            log_error "Failed to create $file_type file: $file_path"
            return 1
        fi
        chmod "$file_perms" "$file_path" || {
            log_error "Failed to set file permissions: $file_path"
            return 1
        }
        $VERBOSE && log_success "Created $file_type file with secure permissions"
    elif [[ ! -r $file_path ]]; then
        log_error "$file_type file exists but is not readable: $file_path"
        return 1
    fi
    
    return 0
}

process_outputfile_init() {
    log_info "Creating output file..."
    
    # Validate header file
    if [[ ! -r $HEADER_FILE ]]; then
        log_error "Header file not found or not readable: $HEADER_FILE"
        return 1
    fi
    
    # Create output directory if it doesn't exist
    local output_dir=${OUTPUT_FILE:h}
    if [[ ! -d $output_dir ]]; then
        if ! mkdir -p "$output_dir" 2>/dev/null; then
            log_error "Failed to create output directory: $output_dir"
            return 1
        fi
        chmod 755 "$output_dir"
        $VERBOSE && log_success "Created output directory with secure permissions"
    fi
    
    # Write YAML frontmatter
    {
        printf "---\n"
        printf "date: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"
        printf "---\n\n"
    } > "$OUTPUT_FILE" || {
        log_error "Failed to write frontmatter"
        return 1
    }
    
    # Append header content
    if ! cat "$HEADER_FILE" >> "$OUTPUT_FILE" 2>/dev/null; then
        log_error "Failed to append header content"
        return 1
    fi
    
    # Add newline for better formatting
    if ! printf "\n" >> "$OUTPUT_FILE" 2>/dev/null; then
        log_error "Failed to append newline"
        return 1
    fi
    
    return 0
}


process_file() {
    local pattern=$1
    local exit_code=0
    
    $VERBOSE && log_info "Processing pattern: $pattern"
    
    # Save current directory
    local original_dir=${PWD}
    cd "$PROJECT_ROOT" || return 1
    
    # Use zsh globbing with error handling
    # Process file directly without globbing since we already have the exact path
    if [ ! -f "$pattern" ]; then
        $VERBOSE && log_warning "File not found: $pattern"
        cd "$original_dir"
        return 0
    fi
    
    local relative_path=${pattern#./}
    
    # Check if file should be excluded
    if should_exclude "$relative_path"; then
        $VERBOSE && log_info "Skipping excluded file: $relative_path"
        ((STATS[skipped_files]++))
        cd "$original_dir"
        return 0
    fi
    
    # Process the file
    if ! process_single_file "$relative_path"; then
        ((STATS[errors]++))
        cd "$original_dir"
        return 1
    fi
    
    ((STATS[processed_files]++))
    
    # Restore original directory
    cd "$original_dir"
    return $exit_code
}

process_single_file() {
    local relative_path=$1
    local full_path="$PROJECT_ROOT/$relative_path"
    
    # Validate file
    if [[ ! -r $full_path ]]; then
        log_error "Cannot read file: $relative_path"
        return 1
    fi
    
    local ext=${$(get_file_extension "$relative_path")}
    local mod_date=${$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$full_path" 2>/dev/null):=Unknown}
    
    log_info "Processing: $relative_path"
    
    # Use a temporary file to avoid partial writes
    local temp_file=$(mktemp)
    {
        printf "---\n"
        printf "File name: %s\n" "$relative_path"
        printf "Last modification: %s\n" "$mod_date"
        printf "---\n\n"
        printf "\`\`\`\`%s\n" "$ext"
        cat "$full_path" 2>/dev/null || { log_error "Failed to read file: $relative_path"; rm "$temp_file"; return 1; }
        printf "\n\`\`\`\`\n\n"
    } > "$temp_file"
    
    # Atomic append to output file
    cat "$temp_file" >> "$OUTPUT_FILE" || { log_error "Failed to write to output file"; rm "$temp_file"; return 1; }
    rm "$temp_file"
    
    $VERBOSE && log_success "Successfully processed: $relative_path"
    return 0
}

process_cursor_rules() {
    local rules_dir="$PROJECT_ROOT/.cursor/rules"
    local temp_rules="/tmp/rules_content.md"
    local found_rules=false
    
    log_header "Processing cursor rules..."
    
    # Always start from PROJECT_ROOT
    cd "$PROJECT_ROOT" || {
        log_warning "Could not access project root, skipping cursor rules processing"
        return 0
    }
    
    # Initialize temp_rules file if we can
    if ! print -l "# Cursor Rules" > "$temp_rules" 2>/dev/null; then
        log_warning "Could not create temporary rules file, skipping cursor rules processing"
        return 0
    fi
    print -l "" >> "$temp_rules"
    
    # Try to process rules from .cursor/rules if it exists
    if [[ -d "$rules_dir" ]]; then
        if find "$rules_dir" -name "*.mdc" -type f 2>/dev/null | grep -q .; then
            found_rules=true
            print -l "## Cursor Rules" >> "$temp_rules"
            print -l "" >> "$temp_rules"
            
            for rule_file in $(find "$rules_dir" -name "*.mdc" -type f 2>/dev/null); do
                process_file "$rule_file" "$temp_rules" || return 1
            done
        fi
    fi
    
    if [ "$found_rules" = true ]; then
        cat "$temp_rules" >> "$OUTPUT_FILE" || {
            log_error "Failed to append cursor rules to output file"
            rm "$temp_rules"
            return 1
        }
    else
        log_info "No cursor rules found"
    fi
    
    rm "$temp_rules"
    return 0
}

process_windsurf_rules() {
    local windsurfrules_file="$PROJECT_ROOT/.windsurfrules"
    local temp_rules="/tmp/rules_content.md"
    local found_rules=false
    
    log_header "Processing windsurf rules..."
    
    # Always start from PROJECT_ROOT
    cd "$PROJECT_ROOT" || {
        log_warning "Could not access project root, skipping windsurf rules processing"
        return 0
    }
    
    # Initialize temp_rules file if we can
    if ! print "# Windsurf Rules\n" > "$temp_rules" 2>/dev/null; then
        log_warning "Could not create temporary rules file, skipping windsurf rules processing"
        return 0
    fi
    print "\n" >> "$temp_rules"
    
    # Process .windsurfrules if it exists
    if [[ -f "$windsurfrules_file" ]]; then
        found_rules=true
        print "## Windsurf Rules\n" >> "$temp_rules"
        print "\n" >> "$temp_rules"
        process_file "$windsurfrules_file" "$temp_rules" || return 1
    fi
    
    if [ "$found_rules" = true ]; then
        cat "$temp_rules" >> "$OUTPUT_FILE" || {
            log_error "Failed to append windsurf rules to output file"
            rm "$temp_rules"
            return 1
        }
    else
        log_info "No windsurf rules found"
    fi
    
    rm "$temp_rules"
    return 0
}

process_codebase() {
    local temp_file="/tmp/codebase_content.md"
    
    log_header "Processing codebase..."
    
    # Always start from PROJECT_ROOT
    cd "$PROJECT_ROOT" || {
        log_warning "Could not access project root, skipping codebase processing"
        return 0
    }
    
    # Initialize temp file
    if ! print "# Codebase Documentation\n" > "$temp_file" 2>/dev/null; then
        log_warning "Could not create temporary file, skipping codebase processing"
        return 0
    fi
    print "\n" >> "$temp_file"
    
    # Process all source code files
    print "## Source Code Files\n" >> "$temp_file"
    print "\n" >> "$temp_file"
    
    # Define file patterns for different categories
    local web_files="*.js,*.jsx,*.ts,*.tsx,*.vue,*.svelte,*.html,*.css,*.scss,*.sass,*.less"
    local backend_files="*.py,*.rb,*.php,*.java,*.go,*.rs,*.cs,*.scala,*.kt,*.swift"
    local config_files="*.json,*.yaml,*.yml,*.toml,*.ini,*.conf"
    local shell_files="*.sh,*.bash,*.zsh,*.fish"
    local doc_files="*.md,*.mdx,*.rst,*.tex"
    local db_files="*.sql,*.prisma,*.graphql"
    
    # Combine all patterns
    local all_patterns="${web_files},${backend_files},${config_files},${shell_files},${doc_files},${db_files}"
    
    # Convert comma-separated patterns to find -name arguments
    local find_args=()
    local IFS=,
    for pattern in $all_patterns; do
        find_args+=(-o -name "$pattern")
    done
    
    # Remove the first -o from find_args
    find_args=("${find_args[@]:1}")
    
    # Common directories to exclude
    local exclude_dirs=(
        "*/node_modules/*"
        "*/dist/*"
        "*/build/*"
        "*/.git/*"
        "*/coverage/*"
        "*/tmp/*"
        "*/.next/*"
        "*/.nuxt/*"
        "*/vendor/*"
        "*/__pycache__/*"
        "*/.pytest_cache/*"
        "*/.venv/*"
        "*/venv/*"
        "*/env/*"
        "*/target/*"
        "*/.env"
        "*/.env.*"
        "*/env.local"
    )
    
    # Build exclude arguments
    local exclude_args=()
    for dir in "${exclude_dirs[@]}"; do
        exclude_args+=(-not -path "$dir")
    done
    
    # Find all source code files, excluding common build and dependency directories
    find . -type f \( "${find_args[@]}" \) \
        "${exclude_args[@]}" \
        2>/dev/null | sort | while read -r file; do
        process_file "$file" "$temp_file" || return 1
    done
    
    # Append to main output
    cat "$temp_file" >> "$OUTPUT_FILE" || {
        log_error "Failed to append codebase content to output file"
        rm "$temp_file"
        return 1
    }
    
    rm "$temp_file"
    return 0
}

process_rules() {
    local exit_code=0
    
    # Process cursor rules
    process_cursor_rules || exit_code=$?
    [ $exit_code -ne 0 ] && return $exit_code
    
    # Process windsurf rules
    process_windsurf_rules || exit_code=$?
    [ $exit_code -ne 0 ] && return $exit_code
    
    return 0
    
    log_info "Checking for rules..."
    
    # Always start from PROJECT_ROOT
    cd "$PROJECT_ROOT" || {
        log_warning "Could not access project root, skipping rules processing"
        return 0
    }
    
    # Initialize temp_rules file if we can
    if ! echo "# Project rules" > "$temp_rules" 2>/dev/null; then
        log_warning "Could not create temporary rules file, skipping rules processing"
        return 0
    fi
    echo "" >> "$temp_rules"
    
    # Try to process rules from .cursor/rules if it exists
    if [ -d "$rules_dir" ]; then
        # Use find with error suppression
        if find "$rules_dir" -name "*.mdc" -type f 2>/dev/null | grep -q .; then
            log_info "Processing .mdc files from $rules_dir"
            while IFS= read -r rule_file; do
                if [ -f "$rule_file" ]; then
                    local filename=$(basename "$rule_file")
                    log_info "Processing rule: $filename"
                    
                    # Extract content after frontmatter
                    awk '
                        BEGIN { in_frontmatter=0; printed=0 }
                        /^---$/ {
                            if (in_frontmatter) {
                                in_frontmatter=0
                                next
                            } else {
                                in_frontmatter=1
                                next
                            }
                        }
                        !in_frontmatter && printed {
                            print
                        }
                        !in_frontmatter && !printed {
                            if (NF) {
                                print
                                printed=1
                            }
                        }
                    ' "$rule_file" >> "$temp_rules" 2>/dev/null && found_rules=true
                    echo "" >> "$temp_rules"
                fi
            done < <(find "$rules_dir" -name "*.mdc" -type f 2>/dev/null)
        else
            log_warning "No .mdc files found, skipping"
        fi
    else
        log_warning "No, Cursor rules directory, skipping"
    fi
    
    # Check for existing .windsurfrules file
    if [ -f "$windsurfrules_file" ]; then
        log_info "Found existing .windsurfrules file"
        if $found_rules; then
            # Only try to update if we found new rules
            if cp "$temp_rules" "$windsurfrules_file" 2>/dev/null; then
                log_success "Rules consolidated in $windsurfrules_file"
            else
                log_warning "Could not update .windsurfrules file"
            fi
        else
            log_info "Using existing .windsurfrules file (no new rules to process)"
        fi
    else
        if $found_rules; then
            if cp "$temp_rules" "$windsurfrules_file" 2>/dev/null; then
                log_success "Created new .windsurfrules file"
            else
                log_warning "Could not create .windsurfrules file"
            fi
        else
            log_warning "No Windsurf rules found, skipping"
        fi
    fi
    
    # Cleanup
    rm -f "$temp_rules" 2>/dev/null
    
    # Always return to SCRIPT_DIR
    cd "$SCRIPT_DIR" 2>/dev/null || true
    
    # Always return success
    return 0
}

get_file_url() {
    local file_path="${1:A}"  # Convert to absolute path
    local repo_root="${$(git rev-parse --show-toplevel):A}"
    
    # Check if file exists locally
    if [[ ! -f "$file_path" ]]; then
        print "Error: File does not exist locally" >&2
        return 1
    fi
    
    # Check if in git repo
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        print "Error: Not in a git repository" >&2
        return 1
    fi
    
    # Get relative path using Zsh parameter expansion
    local rel_path=${file_path#$repo_root/}
    
    local remote_url=$(git config --get remote.origin.url)
    local branch=$(git rev-parse --abbrev-ref HEAD)
    local commit_hash=$(git rev-parse HEAD)
    
    # Extract owner and repo from remote URL
    local owner=""
    local repo=""
    case "$remote_url" in
        git@github.com:*)
            remote_url=${remote_url#git@github.com:}
            remote_url=${remote_url%.git}
            owner=${remote_url%%/*}
            repo=${remote_url#*/}
            ;;
        https://github.com/*)
            remote_url=${remote_url#https://github.com/}
            remote_url=${remote_url%.git}
            owner=${remote_url%%/*}
            repo=${remote_url#*/}
            ;;
        *)
            print "Error: Unsupported remote URL format" >&2
            return 1
            ;;
    esac
    
    # Check if file is tracked by git
    local is_tracked=false
    if git ls-files --error-unmatch "$file_path" > /dev/null 2>&1; then
        is_tracked=true
    fi
    
    # Check if file has uncommitted changes
    local has_changes=false
    if git diff --quiet "$file_path" 2>/dev/null; then
        has_changes=false
    else
        has_changes=true
    fi
    
    # Output status and URLs
    print "File Status:"
    print "------------"
    if [[ "$is_tracked" = false ]]; then
        print "⚠️  File is not yet tracked by git"
        print "→ To track: git add ${rel_path}"
    fi
    if [[ "$has_changes" = true ]]; then
        print "⚠️  File has uncommitted changes"
        print "→ To commit: git commit -m 'your message' ${rel_path}"
    fi
    
    print "\nURLs (after push):"
    print "----------------"
    print "Raw URL: https://raw.githubusercontent.com/${owner}/${repo}/${branch}/${rel_path}"
    print "Web URL: https://github.com/${owner}/${repo}/blob/${branch}/${rel_path}"
    print "API URLs:"
    print "- Contents: https://api.github.com/repos/${owner}/${repo}/contents/${rel_path}?ref=${branch}"
    print "- Git Data: https://api.github.com/repos/${owner}/${repo}/git/blobs/${commit_hash}"
    
    print "\nAPI Usage Examples:"
    print "----------------"
    print "# Get file metadata and content (Base64 encoded):"
    print "curl -H \"Accept: application/vnd.github.v3+json\" \\"
    print "     -H \"Authorization: Bearer \$GITHUB_TOKEN\" \\"
    print "     https://api.github.com/repos/${owner}/${repo}/contents/${rel_path}?ref=${branch}"
    
    print "\n# Get raw file content:"
    print "curl -H \"Accept: application/vnd.github.v3.raw\" \\"
    print "     -H \"Authorization: Bearer \$GITHUB_TOKEN\" \\"
    print "     https://api.github.com/repos/${owner}/${repo}/contents/${rel_path}?ref=${branch}"
    
    # Check if branch exists on remote
    if ! git ls-remote --heads origin "$branch" | grep -q "$branch"; then
        print "\n⚠️  Branch '$branch' doesn't exist on remote yet"
        print "→ To push: git push -u origin $branch"
    fi
}

get_file_urls_only() {
    local file_path="${1:A}"
    local repo_root="${$(git rev-parse --show-toplevel):A}"
    local rel_path=${file_path#$repo_root/}
    
    local remote_url=$(git config --get remote.origin.url)
    local branch=$(git rev-parse --abbrev-ref HEAD)
    local commit_hash=$(git rev-parse HEAD)
    
    # Better URL parsing
    local owner=""
    local repo=""
    
    case "$remote_url" in
        git@github.com:*)
            remote_url=${remote_url#git@github.com:}
            remote_url=${remote_url%.git}
            ;;
        https://github.com/*)
            remote_url=${remote_url#https://github.com/}
            remote_url=${remote_url%.git}
            ;;
        *)
            print "Error: Unsupported remote URL format" >&2
            return 1
            ;;
    esac
    
    # Extract owner and repo
    owner=${remote_url%%/*}
    repo=${remote_url#*/}
    
    print "# URLs for $rel_path:"
    print "raw=https://raw.githubusercontent.com/${owner}/${repo}/${branch}/${rel_path}"
    print "web=https://github.com/${owner}/${repo}/blob/${branch}/${rel_path}"
    print "api_contents=https://api.github.com/repos/${owner}/${repo}/contents/${rel_path}?ref=${branch}"
    print "api_blob=https://api.github.com/repos/${owner}/${repo}/git/blobs/${commit_hash}"
}

# URL management functions
generate_and_display_urls() {
    local file_path=$1
    local url_output
    
    if ! url_output=$(get_file_urls_only "$file_path"); then
        return 1
    fi
    
    # Evaluate URL output in a subshell for safety
    if ! (eval "$url_output" && display_urls); then
        return 1
    fi
    
    return 0
}

# Display generated URLs
display_urls() {
    # Check if any URLs were generated
    if [[ -z ${raw:-} && -z ${web:-} && \
          -z ${api_contents:-} && -z ${api_blob:-} ]]; then
        log_warning "No URLs were generated"
        return 1
    fi
    
    # Display URLs
    print "\n\nKnowledge base URLs (for your AI Architect agent): \n"
    [[ -n ${raw:-} ]] && print "URL for raw content: $raw"
    [[ -n ${web:-} ]] && print "URL for web content: $web"
    [[ -n ${api_contents:-} ]] && print "API for content    : $api_contents"
    [[ -n ${api_blob:-} ]] && print "API for blob       : $api_blob"
    print "\n"
    
    return 0
}

# File cleanup functions
cleanup_output_file() {
    local file=$1
    
    if [[ -z $file ]]; then
        log_error "No file specified for cleanup"
        return 1
    fi
    
    if [[ -f $file ]]; then
        log_info "Cleaning previous file..."
        if ! rm -f "$file" 2>/dev/null; then
            log_error "Failed to remove file: $file"
            return 1
        fi
        $VERBOSE && log_success "Successfully removed previous file"
    else
        $VERBOSE && log_info "No previous file to clean"
    fi
    
    return 0
}

# Git operations functions
handle_git_operations() {
    local file=$1
    
    # Check if file exists and we're in a git repository
    if [[ ! -f $file ]]; then
        $VERBOSE && log_warning "File does not exist: $file"
        return 1
    fi
    
    if [[ ! -d $PROJECT_ROOT/.git ]]; then
        $VERBOSE && log_info "Not a git repository, skipping git operations"
        return 0
    fi
    
    # Stage the file
    stage_file "$file"
}

# Stage a file in git
stage_file() {
    local file=$1
    
    if ! git add "$file" 2>/dev/null; then
        log_warning "Failed to stage file in git: $file"
        return 1
    fi
    
    $VERBOSE && log_success "Staged file in git: $file"
    return 0
}

# Usage examples:
# 1. Get full info:
# get_file_url "README.md"
#
# 2. Get just the URLs:
# eval "$(get_file_urls_only "README.md")"
# echo $raw
# echo $web
# echo $api_contents
# echo $api_blob
#
# 3. Use with curl:
# eval "$(get_file_urls_only "README.md")"
# curl -H "Authorization: Bearer $GITHUB_TOKEN" "$api_contents"



# Process documentation files
process_documentation() {
    print_header "📂 Processing Documentation Files"
    local count=0
    local original_dir
    original_dir=$(pwd) || {
        log_error "Failed to get current directory"
        return 1
    }
    
    # Validate documentation directory
    if [ ! -d "$DOC_DIR" ]; then
        log_warning "Documentation directory not found: $DOC_DIR"
        return 0
    fi
    
    # Change to documentation directory
    if ! cd "$DOC_DIR" 2>/dev/null; then
        log_error "Failed to change to documentation directory"
        return 1
    fi
    
    # Process documentation files using find from project root
    cd "$PROJECT_ROOT" || return 1
    find "$DOC_DIR" -type f \( -name "*.md" -o -name "*.mdx" \) -print0 | while IFS= read -r -d $'\0' file; do
        if [ -f "$file" ]; then
            $VERBOSE && log_info "File detected: $file"
            local relative_path="${file#$PROJECT_ROOT/}"
            file="${file#$PROJECT_ROOT/}"
            
            # Check if file should be excluded
            if should_exclude "$relative_path"; then
                $VERBOSE && log_info "Skipping excluded file: $relative_path"
                ((STATS[skipped_files]++))
                continue
            fi
            
            log_info "Processing: $relative_path"
            if ! process_file "$relative_path"; then
                ((STATS[errors]++))
            else
                ((STATS[processed_files]++))
                ((count++))
            fi
        fi
    done
    
    # Return to original directory
    cd "$original_dir" || log_warning "Failed to return to original directory"
    
    $VERBOSE && log_success "Processed $count documentation files"
    return 0
}

# Process additional files from knowledge list
process_additional_files() {
    print_header "📦 Processing Additional Files"
    local count=0
    
    if [ ! -f "$INCLUDE_FILE" ]; then
        $VERBOSE && log_warning "Include file not found: $INCLUDE_FILE"
        return 0
    fi
    
    printf "\n## Additional Files\n\n" >> "$OUTPUT_FILE"
    printf "> ⚠️ **IMPORTANT**: These files must be taken very seriously as they represent the latest up-to-date versions of our codebase. You MUST rely on these versions and their content imperatively.\n\n" >> "$OUTPUT_FILE"
    
    while IFS= read -r file; do
        # Skip empty lines and comments
        if [ -n "$file" ] && [[ ! "$file" =~ ^#.*$ ]]; then
            # Trim whitespace
            file=$(echo "$file" | xargs)
            
            # Check if file should be excluded
            if should_exclude "$file"; then
                $VERBOSE && log_info "Skipping excluded file: $file"
                ((STATS[skipped_files]++))
                continue
            fi
            
            if ! process_file "$file"; then
                ((STATS[errors]++))
            else
                ((STATS[processed_files]++))
                ((count++))
            fi
        fi
    done < "$INCLUDE_FILE"
    
    $VERBOSE && log_success "Processed $count additional files"
    return 0
}

# Generate project structure
generate_project_structure() {
    print_header "🌳 Project Structure"
    
    if [ ! -d "$PROJECT_ROOT" ]; then
        $VERBOSE && log_warning "Project root not found: $PROJECT_ROOT"
        return 0
    fi
    
    {
        printf "\n### Project Structure\n\n"
        printf "````text\n"
        
        # Read ignore patterns and create tree exclude pattern
        local tree_excludes=""
        if [ -f "$IGNORE_FILE" ]; then
            while IFS= read -r pattern; do
                if [ -n "$pattern" ] && [[ ! "$pattern" =~ ^#.*$ ]]; then
                    pattern=$(echo "$pattern" | xargs)
                    tree_excludes="$tree_excludes|$pattern"
                fi
            done < "$IGNORE_FILE"
            tree_excludes=${tree_excludes#|}  # Remove leading |
        fi
        
        cd "$PROJECT_ROOT" && tree -I "dist|build|coverage|archives|.DS_Store${tree_excludes:+|$tree_excludes}" || {
            log_error "Failed to generate tree structure"
            return 1
        }
        
        printf "````\n\n"
    } >> "$OUTPUT_FILE" || {
        log_error "Failed to write project structure to output file"
        return 1
    }
    
    $VERBOSE && log_success "Generated project structure"
    return 0
}

# Main execution function
main() {
    local exit_code=0
    
    print_header "📘 Generating Knowledge Base"

    
    print_header "📝 Script Setup:"
    printf "    %s: %s\n" "Project Root" "$PROJECT_ROOT"
    printf "    %s: %s\n" "Knowledge Base File" "$KB_FILENAME"
    printf "    %s: %s\n" "Knowledge Base Dir" "$KB_DIR"
    printf "    %s: %s\n" "Documentation Dir" "$DOC_DIR"
    printf "    %s: %s\n" "Codebase Dir" "$CODEBASE_DIR"
    printf "    %s: %s\n" "Ignore File" "$IGNORE_FILE"
    printf "    %s: %s\n" "Include File" "$INCLUDE_FILE"
    printf "    %s: %s\n" "Output File" "$OUTPUT_FILE"
    printf "    %s: %s\n" "Process Mode" "$PROCESS_MODE"
    printf "    %s: %s\n" "Verbose" "$VERBOSE"
    printf "\n"


    # Initialize knowledge base structure
    process_kb_init || exit_code=$?
    [ $exit_code -ne 0 ] && return $exit_code
    
    # Initialize output file
    cleanup_output_file "$OUTPUT_FILE" || exit_code=$?
    [ $exit_code -ne 0 ] && return $exit_code
    
    process_outputfile_init || exit_code=$?
    [ $exit_code -ne 0 ] && return $exit_code
    
    # Process files based on modes
    local modes=(${(s:,:)PROCESS_MODE})
    
    # If no mode specified or mode is 'full', process everything
    if [ -z "$PROCESS_MODE" ] || [[ " ${modes[@]} " =~ " full " ]]; then
        modes=(documentation codebase cursor_rules windsurf_rules)
    fi
    
    # Process each mode
    for mode in ${modes[@]}; do
        case "$mode" in
            documentation)
                process_documentation || exit_code=$?
                [ $exit_code -ne 0 ] && return $exit_code
                ;;
            codebase)
                process_codebase || exit_code=$?
                [ $exit_code -ne 0 ] && return $exit_code
                ;;
            cursor_rules)
                process_cursor_rules || exit_code=$?
                [ $exit_code -ne 0 ] && return $exit_code
                ;;
            windsurf_rules)
                process_windsurf_rules || exit_code=$?
                [ $exit_code -ne 0 ] && return $exit_code
                ;;
        esac
    done
    
    # Always process additional files
    process_additional_files || exit_code=$?
    [ $exit_code -ne 0 ] && return $exit_code
    
    # Generate project structure at the end
    generate_project_structure || exit_code=$?

    # Generate and display URLs
    if [ $exit_code -eq 0 ]; then

        # Print final summary
        print_header "📉 Summary"

        # Print statistics
        print_stats
            
        # Add timestamp at the end of the file
        printf "\n%s\n" "$(date '+%Y-%m-%d %H:%M:%S')" >> "$OUTPUT_FILE" || log_warning "Failed to add timestamp"
        
        # Format with prettier if available
        if command -v prettier &> /dev/null; then
            if [ -f "$OUTPUT_FILE" ]; then
                if command -v pnpm &> /dev/null && ( [ -f "$PROJECT_ROOT/package.json" ] || [ -f "$SCRIPT_DIR/package.json" ] ); then
                    log_info "Formatting generated file with Prettier..."
                    if [ -f "$SCRIPT_DIR/package.json" ]; then
                        cd "$SCRIPT_DIR" && pnpm prettier --write "$OUTPUT_FILE" || log_warning "Failed to format with prettier"
                        cd - &>/dev/null || log_warning "Failed to return to previous directory"
                    else
                        cd "$PROJECT_ROOT" && pnpm prettier --write "$OUTPUT_FILE" || log_warning "Failed to format with prettier"
                        cd - &>/dev/null || log_warning "Failed to return to previous directory"
                    fi
                fi
            fi
        fi

        log_success "Documentation generated in: $OUTPUT_FILE"

        generate_and_display_urls "$OUTPUT_FILE" || log_warning "URL generation failed"
        
    fi

    # Handle git operations
    handle_git_operations "$OUTPUT_FILE" || log_warning "Git operations failed"
    

    return $exit_code
}

# Run main function
main "$@"

# At the end of your script, stage the modified files
