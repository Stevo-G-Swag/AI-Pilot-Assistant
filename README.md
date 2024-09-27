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

1. Open the Xcode project in the `xcode_extension` folder.

2. In Xcode, select the "XcodeGPTPilot" target and choose your development team in the "Signing & Capabilities" tab.

3. Build the project (⌘B).

4. Run the "XcodeGPTPilot" scheme (⌘R). This will launch a new instance of Xcode with the extension installed.

5. In the new Xcode instance, go to Xcode > Settings > Extensions and make sure "XcodeGPTPilot" is enabled.

6. You should now see the Xcode GPT Pilot commands in the Editor menu when editing a file in Xcode.

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

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
