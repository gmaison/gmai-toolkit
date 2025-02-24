#!/bin/zsh

# Set script directory as working directory
PROJECT_ROOT=$(git rev-parse --show-toplevel)
SCRIPT_DIR=${0:a:h}

# Source zsh profile to get environment variables and PATH
if [ -f "$HOME/.zshrc" ]; then
    source "$HOME/.zshrc"
fi

cd "$SCRIPT_DIR" || exit 1

# Configuration
KB_FILENAME="knowledge.md"
RELATIVE_KB_DIR="knowledge_base"
RELATIVE_OUTPUT_FILE="$RELATIVE_KB_DIR/$KB_FILENAME"

KB_DIR="$PROJECT_ROOT/$RELATIVE_KB_DIR"
OUTPUT_FILE="$KB_DIR/$KB_FILENAME"

HEADER_FILE="$KB_DIR/knowledge_header.md"
KNOWLEDGE_LIST="$KB_DIR/knowledge.txt"
SPECS_DIR="$PROJECT_ROOT/documentation"


# Initialize counters
count=0
additional_count=0

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
    printf "%b✗ %b%s%b\n" "$RED" "$NC" "$1" "$NC"
    exit 1
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
    if [ "$ext" = "$filename" ]; then
        echo "txt"
    else
        echo "$ext"
    fi
}

process_kbfolder_init() {

    # Create Knowledge base directory if it doesn't exist
    # ***************************************************
    if [ ! -d "$KB_DIR" ]; then
        mkdir -p "$KB_DIR"
        log_info "Created Knowledge Base Directory"
    fi

    # Create the Header file if it doesn't exist
    # ***************************************************
    if [ ! -f "$HEADER_FILE" ]; then
    
        cat << 'EOF' > $HEADER_FILE
# Project Specifications "Knowledge Base"

This project specifications will help you understand the project architecture and features.

It might not be update to date, always refer to code as source of truth.

 
EOF
        log_info "Created $HEADER_FILE"
    fi

    # Create the knowledge.txt if it doesn't exist
    # ***************************************************
    if [ ! -f "$KNOWLEDGE_LIST" ]; then
        
        cat << 'EOF' > $KNOWLEDGE_LIST
# Specific files to include in the documentation
# Example:
# .cursor/rules/*.mdc
# .windsurfrules
# apps/backend/package.json

EOF
        log_info "Created $KNOWLEDGE_LIST template file"
    fi

}

process_file() {
    local pattern=$1
    
    cd "$PROJECT_ROOT"
    # Use zsh globbing
    for file in $~pattern; do
        if [ -f "$file" ]; then
            local relative_path="${file#./}"
            local full_path="$PROJECT_ROOT/$relative_path"
            local ext=$(get_file_extension "$relative_path")
            log_info "Processing: $relative_path"
            {
                printf "\n### %s\n\n" "$relative_path"
                printf "\`\`\`\`%s\n" "$ext"
                cat "$full_path"
                printf "\n\`\`\`\`\n"
            } >> "$OUTPUT_FILE"
        fi
    done
    cd "$SCRIPT_DIR"
    
    return 0
}

process_rules() {
    local rules_dir="$PROJECT_ROOT/.cursor/rules"
    local windsurfrules_file="$PROJECT_ROOT/.windsurfrules"
    local temp_rules="/tmp/rules_content.md"
    local found_rules=false
    
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

# Function to get just the URLs
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



# Script header
print_header "📚 Generating Documentation"

log_info "Checking knowledge base folder"
process_kbfolder_init

if [ -f "$OUTPUT_FILE" ]; then
    # Initial cleanup
    log_info "Cleaning previous file..."
    rm -f "$OUTPUT_FILE"
fi

log_info "Creating new $OUTPUT_FILE..."
# Add YAML frontmatter with generation date
{
    echo "---"
    echo "date: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "---"
    echo ""
} > "$OUTPUT_FILE"

# Step 1: Copy header
log_info "Adding header file..."
if [ -f "$HEADER_FILE" ]; then
    cat "$HEADER_FILE" >> "$OUTPUT_FILE"
    printf "\n" >> "$OUTPUT_FILE"
    log_success "Header added successfully"
else
    log_warning "Header file not found ($HEADER_FILE)"
fi

# Step 2: Process specification files
print_header "📂 Processing Documentation Files"

# Process documentation files using zsh globbing
cd "$SPECS_DIR"
for file in **/*.{md,mdx}(N.); do
    if [ -f "$file" ]; then
        log_info "Processing: $file"
        {
            cat "$file"
            printf "\n"
        } >> "$OUTPUT_FILE"
        ((count++))
    fi
done

cd "$SCRIPT_DIR"

# After processing specification files
print_header "📋 Processing Rules"
process_rules

#if [ -d "$PROJECT_ROOT/$rules_dir" ]; then
#else
#    log_warning "Rules directory not found, skipping rules processing"
#fi


if [ -f "$KNOWLEDGE_LIST" ]; then
    print_header "📦 Processing Additional Files"
    printf "\n## Additional Files\n\n" >> "$OUTPUT_FILE"
    printf "> ⚠️ **IMPORTANT**: These files must be taken very seriously as they represent the latest up-to-date versions of our codebase. You MUST rely on these versions and their content imperatively.\n\n" >> "$OUTPUT_FILE"
    
    while IFS= read -r file; do
        # Skip empty lines and comments
        if [ ! -z "$file" ] && [[ ! "$file" =~ ^#.*$ ]]; then
            # Trim whitespace
            file=$(echo "$file" | xargs)
            process_file "$file"
            ((additional_count++))
        fi
    done < "$KNOWLEDGE_LIST"
fi

# Add project structure at the end
if [ -d "$PROJECT_ROOT" ]; then
    print_header "🌳 Project Structure"
    {
        printf "\n### Project Structure\n\n"
        printf "````text\n"
        cd "$PROJECT_ROOT" && tree -I "dist|build|coverage|archives|.DS_Store"
        printf "````\n\n"
    } >> "$OUTPUT_FILE"
    log_success "Project structure added successfully"
else
    log_warning "Project root directory not found, skipping project structure"
fi


# Summary
print_header "📊 Summary"
log_success "$count specification files processed"
[ "$additional_count" -gt 0 ] && log_success "$additional_count additional files processed"
log_success "Documentation generated in: $OUTPUT_FILE"

# Add timestamp at the end of the file
printf "\n%s\n" "$(date '+%Y-%m-%d %H:%M:%S')" >> "$OUTPUT_FILE"

if command - v prettier &> /dev/null; then
    # Format the generated file with Prettier
    if [ -f "$OUTPUT_FILE" ]; then
        if command -v pnpm &> /dev/null && ( [ -f "$PROJECT_ROOT/package.json" ] || [ -f "$SCRIPT_DIR/package.json" ] ); then
            log_info "Formatting generated file with Prettier..."
            if [ -f "$SCRIPT_DIR/package.json" ]; then
                cd "$SCRIPT_DIR" && pnpm prettier --write "$OUTPUT_FILE"
            else
                cd "$PROJECT_ROOT" && pnpm prettier --write "$OUTPUT_FILE"
            fi
            log_success "File formatted successfully"
        else
            log_warning "pnpm not found or no package file exists, skipping formatting"
        fi
    else
        log_warning "Output file not found, skipping formatting"
    fi
else
    log_warning "Prettier not installed, skipping formatting"
fi

# At the end of your script, stage the modified files
if [ -f "$OUTPUT_FILE" ]; then
    git add "$OUTPUT_FILE"
fi

eval "$(get_file_urls_only "$OUTPUT_FILE")"
echo "\n\nKnowledge base URLs (for your AI Architect agent): \n"
echo "URL for raw content: $raw"
echo "URL for web content: $web"
echo "API for content    : $api_contents"
echo "API for blob       : $api_blob"
echo "\n\n"
