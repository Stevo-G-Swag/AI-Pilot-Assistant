import SwiftUI

// Add the following struct definitions at the top:
struct AIModel: Identifiable, Decodable {
    let id: String
    let name: String
}

struct Preference: Decodable {
    let key: String
    let value: String
}

struct SettingsView: View {
    @State private var selectedModel = UserDefaults.standard.string(forKey: "SelectedModel") ?? "openai/gpt-4o"
    @State private var models: [AIModel] = []
    @State private var userPreferences: [String: String] = [:]
    @State private var newPreferenceKey = ""
    @State private var newPreferenceValue = ""

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("AI Model")) {
                    Picker("Select AI Model", selection: $selectedModel) {
                        ForEach(models) { model in
                            Text(model.name).tag(model.id)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                
                Section(header: Text("User Preferences")) {
                    ForEach(Array(userPreferences.keys), id: \.self) { key in
                        HStack {
                            Text(key)
                            Spacer()
                            Text(userPreferences[key] ?? "")
                        }
                    }
                    .onDelete(perform: deletePreference)
                    
                    HStack {
                        TextField("Key", text: $newPreferenceKey)
                        TextField("Value", text: $newPreferenceValue)
                        Button(action: addPreference) {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                }
            }
            .listStyle(SidebarListStyle()) // Replaced 'InsetGroupedListStyle' with 'SidebarListStyle'
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .automatic) { // Changed from 'navigationBarTrailing' to '.automatic'
                    Button("Save") {
                        savePreferences()
                        NSApp.stopModal()
                    }
                }
            }
        }
        .frame(width: 400, height: 500)
        .onAppear {
            fetchAvailableModels()
            fetchUserPreferences()
        }
    }
    
    private func fetchAvailableModels() {
        guard let url = URL(string: "http://localhost:5000/api/models") else {
            print("Invalid URL")
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Error fetching models: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else {
                print("No data received")
                return
            }
            
            do {
                let decodedModels = try JSONDecoder().decode([AIModel].self, from: data)
                DispatchQueue.main.async {
                    self.models = decodedModels
                }
            } catch {
                print("Error decoding models: \(error.localizedDescription)")
            }
        }.resume()
    }
    
    private func fetchUserPreferences() {
        guard let url = URL(string: "http://localhost:5000/api/user_preferences?user_id=1") else {
            print("Invalid URL")
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Error fetching user preferences: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else {
                print("No data received")
                return
            }
            
            do {
                let preferences = try JSONDecoder().decode([Preference].self, from: data)
                DispatchQueue.main.async {
                    self.userPreferences = Dictionary(uniqueKeysWithValues: preferences.map { ($0.key, $0.value) })
                }
            } catch {
                print("Error decoding user preferences: \(error.localizedDescription)")
            }
        }.resume()
    }
    
    private func addPreference() {
        guard !newPreferenceKey.isEmpty && !newPreferenceValue.isEmpty else { return }
        userPreferences[newPreferenceKey] = newPreferenceValue
        newPreferenceKey = ""
        newPreferenceValue = ""
    }
    
    private func deletePreference(at offsets: IndexSet) {
        let keysToDelete = offsets.map { Array(userPreferences.keys)[$0] }
        for key in keysToDelete {
            userPreferences.removeValue(forKey: key)
        }
    }
    
    private func savePreferences() {
        UserDefaults.standard.set(selectedModel, forKey: "SelectedModel")
        
        guard let url = URL(string: "http://localhost:5000/api/user_preferences") else {
            print("Invalid URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        for (key, value) in userPreferences {
            let body: [String: Any] = ["user_id": 1, "key": key, "value": value]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("Error saving preference: \(error.localizedDescription)")
                }
            }.resume()
        }
    }
}
