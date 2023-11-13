#!/bin/bash -ex

# Create a new empty flutter project
flutter create e2e_test --empty --platforms android
cd e2e_test

# Replace the contents of "lib/main.dart" with a single print statement.
echo "void main() { print('hello world'); }" >lib/main.dart

# Initialize Shorebird
shorebird init --force -v

# Extract the app_id from the "shorebird.yaml"
APP_ID=$(cat shorebird.yaml | grep 'app_id:' | awk '{print $2}')

# Create a new release on Android
shorebird release android --force -v

# Run the app on Android and ensure that the print statement is printed.
while IFS= read -r line; do
    if [[ "$line" == *"I flutter : hello world"* ]]; then
        adb kill-server
        echo "✅ Test passed!"
        break
    fi
done < <(shorebird preview --release-version 0.1.0+1 --app-id $APP_ID --platform android)

# Replace lib/main.dart "hello world" to "hello shorebird"
sed -i '' 's/hello world/hello shorebird/g' lib/main.dart

# Create a patch
shorebird patch android --force -v

# Run the app on Android and ensure that the original print statement is printed.
while IFS= read -r line; do
    if [[ "$line" == *"I flutter : hello world"* ]]; then
        sleep 5 # Wait for the patch to be installed.
        adb kill-server
        echo "✅ Test passed!"
        break
    fi
done < <(shorebird preview --release-version 0.1.0+1 --app-id $APP_ID --platform android)

# Re-run the app on Android and ensure that the new print statement is printed.
while IFS= read -r line; do
    if [[ "$line" == *"I flutter : hello shorebird"* ]]; then
        adb kill-server
        echo "✅ Test passed!"
        break
    fi
done < <(shorebird preview --release-version 0.1.0+1 --app-id $APP_ID --platform android)

echo "✅ All tests passed!"
exit 0
