//
//  ContentView.swift
//  cortex
//
//  Created by Tanish Pradhan Wong Ah Sui on 7/19/25.
//

import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]
    @State private var screenshotImage: UIImage?
    @State private var isLoadingScreenshot = false
    @State private var screenshotError: String?

    var body: some View {
        NavigationSplitView {
            VStack {
                // Screenshot section
                VStack(spacing: 16) {
                    Text("Mac Screenshot")
                        .font(.headline)
                    
                    if let image = screenshotImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 200)
                            .border(Color.gray, width: 1)
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 200)
                            .overlay(
                                Text("No screenshot")
                                    .foregroundColor(.gray)
                            )
                    }
                    
                    HStack {
                        Button(action: takeScreenshot) {
                            HStack {
                                if isLoadingScreenshot {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "camera")
                                }
                                Text("Take Screenshot")
                            }
                        }
                        .disabled(isLoadingScreenshot)
                        
                        if screenshotImage != nil {
                            Button(action: saveScreenshot) {
                                HStack {
                                    Image(systemName: "square.and.arrow.down")
                                    Text("Save")
                                }
                            }
                        }
                    }
                    
                    if let error = screenshotError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                .padding()

                Button(action: sayHello) {
                    Text("Say Hello")
                }
                
                Divider()
                
                // Items list
                List {
                    ForEach(items) { item in
                        NavigationLink {
                            Text("Item at \(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))")
                        } label: {
                            Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                        }
                    }
                    .onDelete(perform: deleteItems)
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        EditButton()
                    }
                    ToolbarItem {
                        Button(action: addItem) {
                            Label("Add Item", systemImage: "plus")
                        }
                    }
                }
            }
        } detail: {
            Text("Select an item")
        }
    }

    private func sayHello() {
        let serverHost = "localhost"  // <--- set yours here
        let urlString  = "http://\(serverHost):8090/hello"
        guard let url = URL(string: urlString) else {
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            // Handle response if needed
        }.resume()
    }

    private func addItem() {
        withAnimation {
            let newItem = Item(timestamp: Date())
            modelContext.insert(newItem)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
    
    private func takeScreenshot() {
        guard !isLoadingScreenshot else { return }
        
        isLoadingScreenshot = true
        screenshotError = nil
        
        // ───────────────────────────────────────────────────────────
        // Server endpoint
        // -----------------------------------------------------------
        // Using localhost assumes the server runs on-device. In our
        // setup the Flask server runs on the Mac and the iPhone must
        // reach it over the network (USB/Wi-Fi).  Set the host name
        // or IP of the Mac here – e.g. “cortex.local” if you have
        // mDNS/Bonjour enabled, or the Mac’s LAN/Wi-Fi address.
        //
        // For the iOS Simulator, "localhost" is all you need.
        //
        // Example values:
        //   "localhost"                (for iOS Simulator)
        //   "cortex.local"              (Bonjour)
        //   "192.168.0.23"             (same Wi-Fi subnet)
        //   "172.20.10.1"              (USB Personal Hotspot)
        //
        let serverHost = "localhost"  // <--- set yours here
        let urlString  = "http://\(serverHost):8090/screenshot"
        guard let url = URL(string: urlString) else {
            screenshotError = "Invalid URL"
            isLoadingScreenshot = false
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                self.isLoadingScreenshot = false
                
                if let error = error {
                    self.screenshotError = "Network error: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    self.screenshotError = "No data received"
                    return
                }
                
                do {
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    
                    if let success = json?["success"] as? Bool, success,
                       let base64String = json?["image"] as? String,
                       let imageData = Data(base64Encoded: base64String) {
                        self.screenshotImage = UIImage(data: imageData)
                    } else {
                        let errorMessage = json?["error"] as? String ?? "Unknown error"
                        self.screenshotError = "Screenshot failed: \(errorMessage)"
                    }
                } catch {
                    self.screenshotError = "JSON parsing error: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
    
    private func saveScreenshot() {
        guard let image = screenshotImage else { return }
        
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        
        // Show success feedback
        let alert = UIAlertController(title: "Saved", message: "Screenshot saved to Photos", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(alert, animated: true)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
