#!/bin/sh
set -e

# current branch feat/xxxx-xxxx
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

ENV_FOR_TAG="dev"

LAST_MASTER_VERSION= #Last version on origin master, fetched from package.json 
CURRENT_PROJECT_VERSION= #current version on current branch, fetched from package.json

TAG_VERSION=
# Example dev: v2.0.0-feature-branch-name-dev-v1 
# Example stage: v2.0.0-feature-branch-name-stage-v1
# Example prod: v2.0.0

CURRENT_VERSION_AND_MASTER_VERSION_ARE_EQUAL= # Boolean to check if master and current branch versions are equal

TAG_VERSION_NUMBER= # Example: v2.0.0

# Initialize the log flag
enable_log=false

# No Verify commit
no_verify=false

# Check for the -log argument
for arg in "$@"; do
    if [ "$arg" == "log" ]; then
        enable_log=true
        break
    fi
     if [ "$arg" == "no-verify" ]; then
        no_verify=true
        break
    fi
done

# Function to log messages
log() {
    if [ "$enable_log" == true ]; then
        echo "$1"
    fi
}

generateBuild() {
    npm run buildId
}

compareCurrentAndMasterVersions() {
    VERSION_CURRENT=$1
    VERSION_MASTER=$2

    echo "Comparing current version $VERSION_CURRENT with master version $VERSION_MASTER"

    # Compare CURRENT_VERSION_NUMBER and LAST_VERSION_NUMBER
    if [ "$VERSION_CURRENT" != "$VERSION_MASTER" ]; then
        CURRENT_VERSION_AND_MASTER_VERSION_ARE_EQUAL=false

        # Master might be 3.0.0 and current branch might be 2.4.1
        # In this case, compare all digits between; if master is greater in any, ask to update and merge master
        compare_versions "$VERSION_CURRENT" "$VERSION_MASTER"
    else
        CURRENT_VERSION_AND_MASTER_VERSION_ARE_EQUAL=true
        echo "Your version is the same as the master version; you need to update it"
    fi
}

checkIfHaveChanges() {
    # Check for uncommitted changes
    status=$(git status --porcelain)

    if [ -z "$status" ]; then
        echo ""
    else
        echo "There are uncommitted changes in Git. Please commit your changes before creating a tag."
        exit 0
    fi
}

updateVersionHistoryMD() {
    if [ "$CURRENT_VERSION_AND_MASTER_VERSION_ARE_EQUAL" == "false" ]; then
        return 
    fi

    echo "Updating versionHistoryMD...\n"
    echo "We will update versionHistory.md with your inputs"
    echo "Please choose the type of code change you will introduce:"
    echo "1) Feature"
    echo "2) Fix"

    read -e -p "Enter the number of your choice (1, 2, or 3): " choice; printf '%s\n' "$choice"

    case $choice in
        1)
            type="Feat"
            ;;
        2)
            type="Fix"
            ;;
        *)
            echo "Invalid choice. Please run the script again and select either 1 or 2."
            exit 1
            ;;
    esac

    # Introduce message/title for versionHistory.md
    echo "Please enter your message describing the change: \n"
    read -e -p "" _msg; printf '%s\n' "$_msg"

    formatted_msg=$(echo "$_msg" | awk '{print toupper(substr($0, 1, 1)) tolower(substr($0, 2))}')

    USER_MESSAGE_VERSION="$type: $formatted_msg"
    log "Your version history message is: '$USER_MESSAGE_VERSION'"

    # Define the new lines to be added
    newLines="Buyer Checkout Version history\n## 🏷️ $TAG_VERSION_NUMBER\n* $USER_MESSAGE_VERSION"

    # Create a temporary file
    tempFile=$(mktemp)

    # Add the new lines to the temporary file
    echo "$newLines" > "$tempFile"

    # Append the contents of versionHistory.md starting from the second line to the temporary file
    tail -n +2 versionHistory.md >> "$tempFile"

    # Replace the original file with the new file
    mv "$tempFile" versionHistory.md

    log "Running version patch to update package.json version and package-lock.json"
}

getMasterPackageJsonVersion() {
    if [ "$CURRENT_BRANCH" == "master" ]; then
        echo "You need to be on your feature branch, not on the master branch."
        exit 1
    fi

    log "Getting package.json from master branch...\n"
    # Retrieve package.json from master branch

    echo "--------Switching to master to fetch package.json version--------"
    git checkout master
    git pull origin master

    # Save the content of package.json in a variable
    PACKAGE_JSON_CONTENT=$(cat package.json)

    # Extract the version number using grep and sed
    LAST_MASTER_VERSION=$(echo "$PACKAGE_JSON_CONTENT" | grep '"version"' | sed -E 's/.*"version": "([^"]+)".*/\1/')

    # Print the extracted version (for verification)
    echo "Last master version: $LAST_MASTER_VERSION"

    log ""--------Switching back to your current branch"--------"
    git checkout $CURRENT_BRANCH 
}

getCurrentVersionOfProject() {
    # Get current package.json
    PACKAGE_JSON_CONTENT=$(cat package.json)
    CURRENT_PROJECT_VERSION=$(echo "$PACKAGE_JSON_CONTENT" | grep '"version"' | sed -E 's/.*"version": "([^"]+)".*/\1/')
}

bumpVersionBasedOnSizeOfChange() {
    if [ "$CURRENT_VERSION_AND_MASTER_VERSION_ARE_EQUAL" == "false" ]; then
        TAG_VERSION_NUMBER="$CURRENT_PROJECT_VERSION"
        return
    fi

    echo "\n\nPlease choose the size of the change you will introduce:"
    echo "1) Simple and small fix or feature"
    echo "2) Significant feature with major changes" 
    echo "3) Major change to the project"

    read -e -p "Please enter the number: " _choice; printf '%s\n' "$_choice"

    # Save new version into [TAG_VERSION_NUMBER]
    case $_choice in
        1)  
            size="small"
            bumpVersionNumber "$CURRENT_PROJECT_VERSION" "$size"
            ;;
        2)  
            size="medium"
            bumpVersionNumber "$CURRENT_PROJECT_VERSION" "$size"
            ;;
        3)
            size="big"
            bumpVersionNumber "$CURRENT_PROJECT_VERSION" "$size"
            ;;
        *)
            echo "Invalid choice. Please run the script again and select either 1, 2, or 3."
            exit 1
            ;;
    esac
}

commitBuildIdAndBumpVersion() {
    echo "Committing Build ID, package.json, and versionHistory.md...\n"
    npm run buildId
    no_version_set=""
    if [ "$no_verify" == "true" ]; then
      no_version_set="--no-verify"
    fi
    
    local commit_message="Bump version to $TAG_VERSION_NUMBER"

    npm run format > /dev/null 2>&1 && git add . 
    if [ "$CURRENT_VERSION_AND_MASTER_VERSION_ARE_EQUAL" == "false" ]; then
        commit_message="Generate build id and tag version"
    fi

    git commit -m "$commit_message" $no_version_set && git push 
}

bumpVersionNumber() {
    initial_version=$1
    size=$2

    echo "Bumping version number from current version: $initial_version...\n" 

    # If size == small return 1 and medium return 2 and large return 3
    if [ "$size" == "big" ]; then
        field_number=1
    fi
    if [ "$size" == "medium" ]; then
        field_number=2
    fi
    if [ "$size" == "small" ]; then
        field_number=3
    fi

    IFS='.' read -r major minor patch <<< "${initial_version#v}"

    if [ "$size" == "big" ]; then
        # Increment the major version and reset minor and patch to 0
        new_major=$((major + 1))
        new_version="v${new_major}.0.0"
    fi
    if [ "$size" == "medium" ]; then
        # Increment the minor version and reset patch to 0
        new_minor=$((minor + 1))
        new_version="v${major}.${new_minor}.0"
    fi
    if [ "$size" == "small" ]; then
        # Increment the patch version
        new_patch=$((patch + 1))
        new_version="v${major}.${minor}.${new_patch}"
    fi

    TAG_VERSION_NUMBER="$new_version"
    echo "NEW TAG VERSION CREATED!!: $TAG_VERSION_NUMBER \n"
    # npm version 
}

askForEnvironmentVersion() {
    log "Asking for environment version to deploy...\n"

    echo "\n\n You are about to create a new tag for deployment. Tell me the environment to deploy to \n"
    echo "Please choose the environment to deploy:"
    echo "1) Dev"
    echo "2) Stage"
    echo "3) Prod"

     read -e -p "Enter the number of your choice (1, 2, or 3): " choice; printf '%s\n' "$choice"

    case $choice in
        1)
            ENV_FOR_TAG="dev"
            ;;
        2)
            ENV_FOR_TAG="stage"
            ;;
        3)
            ENV_FOR_TAG="prod"
            ;;
        *)
            echo "Invalid choice. Please run the script again and select either 1, 2, or 3."
            exit 1
            ;;
    esac

}

generateCompleteTagBasedOnEnvironment() {
    echo "Generating complete tag based on environment...\n"
    log "Environment is set to: $ENV_FOR_TAG"

    # Conditional logic based on the environment
    if [ "$ENV_FOR_TAG" = "dev" ] || [ "$ENV_FOR_TAG" = "stage" ]; then
        log "Dev and Stage environment structure is as follows. e.g: v2.0.0-feature-branch-dev-v1"

        # Normalize the branch name by removing '/' and replacing with '-'
        normalized_branch_name=$(echo "$CURRENT_BRANCH" | sed 's/\//-/g')

        current_tag_version_by_env_root="$TAG_VERSION_NUMBER-$normalized_branch_name-$ENV_FOR_TAG-v"

        # Get the latest tag that matches the pattern
        latest_tag=$(git tag -l "${current_tag_version_by_env_root}[0-9]*" | sort -V | tail -n 1)

        # Check if a matching tag was found
        if [ -z "$latest_tag" ]; then
            echo "No tags found matching the pattern."
            val="1"
            TAG_VERSION="$current_tag_version_by_env_root$val"
            printAndGenerateGitTag
            return 
        fi

        echo "Latest tag found in git tag -l: $latest_tag"

        last_v_number=$(echo "$latest_tag" | awk -F'-' '{print $NF}' | grep -o 'v[0-9]*' | grep -o '[0-9]*')

        log "Latest tag number version: $last_v_number"

        if [ -z "$last_v_number" ]; then
            echo "Failed to extract version number from the latest tag."
            exit 1
        fi

        last_v_number=$((last_v_number + 1))
        # Check if version_number was extracted successfully

        # Construct the new tag version
        TAG_VERSION="${current_tag_version_by_env_root}${last_v_number}"

        printAndGenerateGitTag

    elif [ "$ENV_FOR_TAG" = "prod" ]; then
        echo "Running commands for production environment"
        echo "Performing tasks specific to production"
        echo "Generating new tag for production environment"
        echo "Deploying to production server"

        git tag $TAG_VERSION_NUMBER
    else
        echo "Unknown environment: $ENV_FOR_TAG"
        exit 1
    fi
}

printAndGenerateGitTag() {
    echo "Generated git tag: $TAG_VERSION successfully!!"
    git tag $TAG_VERSION
    git push origin $TAG_VERSION
}

updatePackageJson() {
    local version=${1#v}

    # Regular expression to match "x.x.xx" or "x.x.x"
    local regex='^[0-9]+\.[0-9]+\.[0-9]+$'

    # Validate the version string
    if [[ ! $version =~ $regex ]]; then
        echo "Invalid version format. Use x.x.xx or x.x.x where x is a number."
        exit 1
    fi

    # Update the version in package.json
    if [ ! -f package.json ]; then
        echo "package.json not found"
        exit 1
    fi

    # Use sed to update the version in package.json
    sed -i.bak -E "s/\"version\": \"[0-9]+\.[0-9]+\.[0-9]+\"/\"version\": \"$version\"/" package.json
    
    if [ $? -eq 0 ]; then
        rm -f package.json.bak
        echo "Version updated to $version in package.json"
    else
        echo "Failed to update version in package.json"
        exit 1
    fi
}

# Function to compare two numbers
compare_numbers() {
    if [ "$1" -gt "$2" ]; then
        echo "--------The master version is higher version. Please merge master and update your branch.--------"
        exit 0
    elif [ "$1" -lt "$2" ]; then
        echo "--------The current version is higher than master; no update needed--------."

    fi
}

# Function to compare version changes
compare_versions() {
    # Remove the prefix 'v'
    local master_version=${1#v}
    local current_version=${2#v}

    # Split the versions into arrays
    IFS='.' read -r -a master_version_parts <<< "$LAST_MASTER_VERSION"
    IFS='.' read -r -a current_version_parts <<< "$CURRENT_PROJECT_VERSION"

    for i in "${!master_version_parts[@]}"; do
        compare_numbers "${master_version_parts[$i]}" "${current_version_parts[$i]}"
    done
}

printAllChanges() {
  echo "\n Tag Version created successfuly!!: $TAG_VERSION"
}

# Check if there are uncommitted changes
checkIfHaveChanges

# 0) Get the master version from master branch's package.json
getMasterPackageJsonVersion

# 1) Get the current version from package.json
getCurrentVersionOfProject

# 2) Compare versions and if they are equal, generate a version history
compareCurrentAndMasterVersions "$CURRENT_PROJECT_VERSION" "$LAST_MASTER_VERSION"

# 3) Print current and last master version
echo "$CURRENT_PROJECT_VERSION CURRENT_PROJECT_VERSION"
echo "$LAST_MASTER_VERSION LAST_MASTER_VERSION"

# 4) Ask for environment to push
askForEnvironmentVersion

# 5) Generate version based on the size of change (small, medium, large) 
# For instance, small changes are: 2.0.1 to 2.0.2 | medium changes are: 2.0.0 to 2.1.0 | large changes are: 2.0.0 to 3.0.0
bumpVersionBasedOnSizeOfChange

# 6) Update npm package version
updatePackageJson "$TAG_VERSION_NUMBER"

# 7) Update versionHistoryMD and package.json if necessary
updateVersionHistoryMD

# 8) Generate git tag name based on environment (dev|stage|prod)
generateCompleteTagBasedOnEnvironment

# 9) Generate build ID
commitBuildIdAndBumpVersion

# 10) print success message saying all changes made.
printAllChanges
