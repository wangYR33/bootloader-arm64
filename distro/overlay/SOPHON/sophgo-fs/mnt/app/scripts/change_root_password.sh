#!/bin/sh

PASSFILE="/etc/password.txt"

# Check for parameter
if [ -z "$1" ]; then
    echo "ERROR: Please provide the new password as a parameter."
    echo "Usage: ./change_root_password.sh 'NewPassw0rd!'"
    exit 1
fi

NEW_PASS="$1"

validate_password() {
    pass="$1"

    # Length check
    if [ "$(echo "$pass" | wc -c)" -lt 7 ]; then
        echo "ERROR: Password must be at least 6 characters long."
        return 1
    fi

    # Uppercase letter check
    echo "$pass" | grep -q '[A-Z]'
    if [ $? -ne 0 ]; then
        echo "ERROR: Password must contain at least one uppercase letter."
        return 1
    fi

    # Lowercase letter check
    echo "$pass" | grep -q '[a-z]'
    if [ $? -ne 0 ]; then
        echo "ERROR: Password must contain at least one lowercase letter."
        return 1
    fi

    # Digit check
    echo "$pass" | grep -q '[0-9]'
    if [ $? -ne 0 ]; then
        echo "ERROR: Password must contain at least one digit."
        return 1
    fi

    # Special character check
    echo "$pass" | grep -q '[\@\#\%\&\!\$\^\_\-\+]'
    if [ $? -ne 0 ]; then
        echo "ERROR: Password must contain at least one special character (@#%&!$^_-+)."
        return 1
    fi

    return 0
}

# Validate the password
validate_password "$NEW_PASS"
if [ $? -ne 0 ]; then
    echo "Password validation failed."
    exit 1
fi

# Save password to file
echo "$NEW_PASS" > "$PASSFILE"
chmod 600 "$PASSFILE"
echo "Password has been saved to: $PASSFILE"

# Change root password
echo "root:$NEW_PASS" | chpasswd

if [ $? -eq 0 ]; then
    echo "Root password updated successfully."
else
    echo "Failed to update root password."
    exit 1
fi
