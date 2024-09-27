# Xcode GPT Pilot

Xcode GPT Pilot is an AI-powered Xcode extension for intelligent code generation and assistance using a Flask backend and the Xcode extension framework.

## Setup Instructions

### Prerequisites

- Xcode 12.0 or later
- Python 3.7 or later
- pip (Python package installer)

### Backend Setup

1. Clone the repository:
   ```
   git clone https://github.com/your-username/xcode-gpt-pilot.git
   cd xcode-gpt-pilot
   ```

2. Set up a virtual environment (optional but recommended):
   ```
   python3 -m venv venv
   source venv/bin/activate
   ```

3. Install the required Python packages:
   ```
   pip install -r requirements.txt
   ```

4. Set up environment variables:
   Create a `.env` file in the project root and add the following:
   ```
   OPENAI_API_KEY=your_openai_api_key
   OPENROUTER_API_KEY=your_openrouter_api_key
   HUGGINGFACE_API_KEY=your_huggingface_api_key
   GITHUB_API_KEY=your_github_api_key
   DATABASE_URL=your_database_url
   ```

5. Run the Flask backend:
   ```
   python backend/main.py
   ```
   The backend will start running on `http://localhost:5000`.

### Xcode Extension Setup

1. Open the Xcode project in the `xcode_extension` folder:
   ```
   open xcode_extension/XcodeGPTPilot.xcodeproj
   ```

2. In Xcode, select the "XcodeGPTPilot" target and choose your development team in the "Signing & Capabilities" tab.

3. Build the project (⌘B).

4. Run the "XcodeGPTPilot" scheme (⌘R). This will launch a new instance of Xcode with the extension installed.

5. In the new Xcode instance, go to Xcode > Settings > Extensions and make sure "XcodeGPTPilot" is enabled.

6. You should now see the Xcode GPT Pilot commands in the Editor menu when editing a file in Xcode.

### Detailed Xcode Extension Setup

1. Building the Extension:
   - After opening the Xcode project, ensure you're using the latest Swift version compatible with your Xcode.
   - If you encounter any build errors, go to File > Packages > Update to Latest Package Versions to update dependencies.
   - Clean the build folder (Shift + ⌘ + K) before building if you've made significant changes.

2. Running the Extension:
   - When you run the "XcodeGPTPilot" scheme, it will launch a new instance of Xcode. This is normal and is how Xcode tests extensions.
   - If the new Xcode instance doesn't launch, check the console for any error messages and ensure your Mac's security settings allow launching new applications.

3. Enabling the Extension:
   - In the new Xcode instance, if you don't see the Extensions menu, restart Xcode and check again.
   - If the extension is still not visible, go to System Preferences > Extensions and ensure that Xcode Source Editor extensions are enabled.

4. Troubleshooting:
   - If changes to the extension code are not reflected, try cleaning the build folder, rebuilding, and relaunching the extension.
   - Ensure that the Flask backend is running before using the extension. The extension relies on the backend for AI-powered features.
   - If you encounter permission issues, ensure that Xcode has the necessary permissions in System Preferences > Security & Privacy > Privacy > Developer Tools.

## Usage

1. Open a Swift file in Xcode.

2. Use the following commands from the Editor menu:
   - Generate Code: Generates code based on the selected text or current context.
   - Suggest Refactoring: Provides refactoring suggestions for the selected code.
   - Settings: Configure AI models and user preferences.
   - Collaboration: Access real-time collaboration features.
   - Recommend Learning Resources: Get personalized learning resource recommendations.

3. The extension communicates with the Flask backend to provide AI-powered assistance.

## Troubleshooting

- If you encounter any issues with the Xcode extension, try cleaning the build folder (Shift + ⌘ + K) and rebuilding the project.
- Make sure the Flask backend is running and accessible at `http://localhost:5000`.
- Check the Xcode console for any error messages related to the extension.
- If the extension is not appearing in the Editor menu, try disabling and re-enabling it in Xcode > Settings > Extensions.
- For collaboration features, ensure that your network allows WebSocket connections.
- If you're experiencing slow response times, check your internet connection and the status of the OpenAI API.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
