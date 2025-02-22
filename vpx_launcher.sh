#!/bin/bash
# VPX Table Launcher
# A simple GUI launcher for Visual Pinball X tables
# Tarso Galvão - 2025
# Dependencies: yad 0.40.0 (GTK+ 3.24.38)

# fix: app moves to mouse pointer when exiting a game (keep it centered/fixed)

# Check for dependencies
if ! command -v yad &>/dev/null; then
    echo "Error: 'yad' is not installed. Please install 'yad' and try again."
    echo "For Debian-based systems, run: sudo apt install yad"
    exit 1
fi

# Check for graphical environment
if [ -z "$DISPLAY" ]; then
    echo "This script requires a graphical environment!"
    exit 1
fi

## --------------------- CONFIGURATION ---------------------
# Config file path
CONFIG_FILE="$HOME/.vpx_launcher_config"

# Launcher will run "START_ARGS COMMAND_TO_RUN -play TABLE_FILE END_ARGS"
# Example: DRI_PRIME=1 gamemoderun /path/to/VPinballX_GL -play /path/to/table.vpx

# Load or create the config file
if [ ! -f "$CONFIG_FILE" ]; then
    {
        echo "TABLES_DIR=\"$HOME/Games/vpinball/build/tables/\""
        echo "START_ARGS=\"$START_ARGS\""
        echo "COMMAND_TO_RUN=\"$HOME/Games/vpinball/build/VPinballX_GL\""
        echo "END_ARGS=\"$END_ARGS\""
    } > "$CONFIG_FILE"
fi

# (Re)Load the config file
# shellcheck source=$HOME/.vpx_launcher_config
source "$CONFIG_FILE"

## ------------- INI SETTINGS (Standalone) ---------------
open_ini_settings() {
    # Check for Python 3 and Python3-tk
    if ! command -v python3 &>/dev/null; then
        yad --form --title="Error" --width=400 --height=200 \
            --field="Missing dependency: Python3\nINI Editor cannot be run.\n\n \
                Do you want to install it now? (Requires sudo)\n":LBL \
            --field="You can also install it manually using:\n \
                 sudo apt install python3 python3-tk":LBL \
            --button="Yes:0" --button="Back:1"

        if [ $? -eq 0 ]; then
            # User chose to install Python3
            sudo apt install -y python3 python3-tk
        else
            # User chose not to install Python3
            return
        fi
    fi

    # Check if a parameter (INI file) was passed
    if [ -n "$1" ]; then
        # If so, pass it to the Python script
        python3 vpx_ini_editor.py "$1"
    else
        # Otherwise, open the default INI editor
        python3 vpx_ini_editor.py
    fi
}

## ------------------ LAUNCHER SETTINGS -------------------
open_launcher_settings() {
    # Show settings dialog
    NEW_VALUES=$(yad --form --title="Settings" \
        --field="Tables Directory:":DIR "$TABLES_DIR" \
        --field="Initial Arguments:":FILE "$START_ARGS" \
        --field="VPX Executable:":FILE "$COMMAND_TO_RUN" \
        --field="Final Arguments:":FILE "$END_ARGS" \
        --width=500 --height=150 \
        --separator="|")

    if [ -z "$NEW_VALUES" ]; then return; fi

    # Extract new values
    NEW_TABLES_DIR=$(echo "$NEW_VALUES" | cut -d '|' -f1)
    NEW_START_ARGS=$(echo "$NEW_VALUES" | cut -d '|' -f2)
    NEW_COMMAND=$(echo "$NEW_VALUES" | cut -d '|' -f3)
    NEW_END_ARGS=$(echo "$NEW_VALUES" | cut -d '|' -f4)

    # Validate new directory
    if [ ! -d "$NEW_TABLES_DIR" ] || ! find "$NEW_TABLES_DIR" -type f -name "*.vpx" | grep -q .; then
        yad --title="Error" --text="Error: No .vpx files found in the directory!" \
            --form --width=400 --height=150 \
            --buttons-layout=center \
            --button="Retry:1" --button="Exit:252"

        if [ $? -eq 252 ]; then
            exit 0  # Exit the script
        fi

        open_launcher_settings
        return  # Retry after settings update
    fi

    # Validate new executable
    if [ ! -x "$NEW_COMMAND" ]; then
        yad --title="Error" --text="Error: The executable '$NEW_COMMAND' does not exist or is not executable!" \
            --form --width=400 --height=150 \
            --buttons-layout=center \
            --button="Retry:1" --button="Exit:252"

        if [ $? -eq 252 ]; then
            exit 0  # Exit the script
        fi

        open_launcher_settings
        return  # Retry after settings update
    fi

    # Save settings
    {
        echo "TABLES_DIR=\"$NEW_TABLES_DIR\""
        echo "START_ARGS=\"$NEW_START_ARGS\""
        echo "COMMAND_TO_RUN=\"$NEW_COMMAND\""
        echo "END_ARGS=\"$NEW_END_ARGS\""
    } > "$CONFIG_FILE"

    # Give user feedback
    yad --info --title="Settings" \
        --text="                    Paths updated successfully!" \
        --buttons-layout=center --button="OK:0" \
        --width=300 --height=100 2>/dev/null

    # Reload the config file
    # shellcheck source=$HOME/.vpx_launcher_config
    source "$CONFIG_FILE"
}

# ## --------------------- MAIN LOOP ---------------------
while true; do
    # Ensure valid .vpx files exist on launch
    if ! find "$TABLES_DIR" -type f -name "*.vpx" | grep -q .; then
        yad --title="Error" --text="No .vpx files found in $TABLES_DIR." 2>/dev/null \
        --form --width=400 --height=150 \
        --buttons-layout=center \
        --button="Settings:1" --button="Exit:252"

        if [ $? -eq 252 ]; then
            exit 0  # Exit the script
        fi

        open_launcher_settings
        continue  # Retry after settings update
    fi

    # Ensure the executable is valid on launch
    if [ ! -x "$COMMAND_TO_RUN" ]; then
        yad --title="Error" --text="The executable '$COMMAND_TO_RUN' does not exist or is not executable!" 2>/dev/null \
        --form --width=400 --height=150 \
        --buttons-layout=center \
        --button="Settings:1" --button="Exit:252"

        if [ $? -eq 252 ]; then
            exit 0  # Exit the script
        fi

        open_launcher_settings
        continue  # Retry after settings update
    fi

    # Create file list
    FILE_LIST=() # Array to store table names
    declare -A FILE_MAP # Associative array to map names to paths
    TABLE_NUM=0  # Initialize counter for table count
    DEFAULT_ICON="./default_icon.png"  # Set a default icon

    # Read all .vpx files in the tables directory
    while IFS= read -r FILE; do
        BASENAME=$(basename "$FILE" .vpx) # Get the file name without extension
        ICON_PATH="${FILE%.vpx}.ico"  # Try to find an icon with the same name

        # Use the default icon if the image does not exist
        if [ ! -f "$ICON_PATH" ]; then
            ICON_PATH="$DEFAULT_ICON"
        fi

        FILE_LIST+=("$ICON_PATH" "$BASENAME")  # Add the icon and name to the list
        FILE_MAP["$BASENAME"]="$FILE" # Map the name to the full path
        ((TABLE_NUM++))  # Increment table counter
    done < <(find "$TABLES_DIR" -type f -name "*.vpx" | sort)

    # Prepare the list for yad (newline-separated)
    FILE_LIST_STR=$(printf "%s\n" "${FILE_LIST[@]}")

    ## ----------- TABLE SELECTION MENU ------------
    while true; do
        # Show launcher menu
        SELECTED_NAME=$(yad --list --title="VPX Launcher" \
            --text="Table(s) found: $TABLE_NUM" \
            --width=600 --height=400 \
            --button="INI Editor:2" --button="Extract VBS:10" \
            --button="⚙:1" --button="🕹️ :0" --button="🚪 :252" \
            --no-headers \
            --column="Icon:IMG" --column="Table Name" <<< "$FILE_LIST_STR" 2>/dev/null)

        EXIT_CODE=$?

        if [ $EXIT_CODE -eq 1 ]; then
            open_launcher_settings
            continue  # Reload after settings update

        elif [ $EXIT_CODE -eq 2 ]; then         
            # If INI Editor is pressed, check if a table is selected
            if [ -z "$SELECTED_NAME" ]; then
                # No table selected, open default INI editor
                open_ini_settings
            else
                # Table selected, open the corresponding INI file
                # Strip the leading and trailing pipe characters
                SELECTED_NAME=$(echo "$SELECTED_NAME" | sed 's/^|//;s/|$//')
                # Get the absolute INI file path
                INI_FILE="${FILE_MAP[$SELECTED_NAME]%.vpx}.ini"
                open_ini_settings "$INI_FILE"
            fi
            continue  # Return to the menu after editing INI file

        elif [ $EXIT_CODE -eq 10 ]; then
            # Extract VBS script from the selected table
            if [ -z "$SELECTED_NAME" ]; then
                # Show warning if no table is selected
                yad --title="Attention" --text="No table selected!\nPlease select a table before extracting." \
                    --width=400 --height=150 --buttons-layout=center --button="OK:0"
                continue  # Return to the list
            fi
            # Extract the selected table name
            SELECTED_NAME=$(echo "$SELECTED_NAME" | sed 's/^|//;s/|$//')
            # Get full file path
            SELECTED_FILE="${FILE_MAP[$SELECTED_NAME]}"

            # Extract the VBS script
            eval "\"$COMMAND_TO_RUN\" -ExtractVBS \"$SELECTED_FILE\"" &
            wait $!

            # Give user feedback
            yad --info --title="VBS Extract" \
                --text="VBS script extracted successfully!" \
                --buttons-layout=center --button="OK:0" \
                --width=300 --height=100 2>/dev/null

            continue  # Return to the list

        elif [ $EXIT_CODE -eq 252 ]; then
            exit 0  # User canceled

        elif [ -z "$SELECTED_NAME" ]; then
            # Show warning if no table is selected
            yad --title="Attention" --text="No table selected!\nPlease select a table before launching." \
                --width=400 --height=150 --buttons-layout=center --button="OK:0"
            continue  # Return to the list
        fi

        break  # Exit loop if a valid table is selected
    done

    ## ----------- RUN THE SELECTED TABLE ------------
    # Extract the selected table name (first field from yad output)
    SELECTED_NAME=$(echo "$SELECTED_NAME" | awk -F '|' '{print $2}')

    # Get full file path
    SELECTED_FILE="${FILE_MAP[$SELECTED_NAME]}"

    # Run the selected file with "-play" added automatically
    eval "$START_ARGS \"$COMMAND_TO_RUN\" -play \"$SELECTED_FILE\" $END_ARGS" &

    # Wait for it to finish
    wait $!

done
