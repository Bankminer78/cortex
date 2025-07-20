//
//  NetworkService.swift
//  cortex
//
//  Created by Tanish Pradhan Wong Ah Sui on 7/19/25.
//
import Foundation
import UIKit

// JSON response structure
struct ScreenshotResponse: Codable {
    let status: String
    let image: String?
}

class NetworkService {
    func fetchScreenshot() async -> UIImage? {
        guard let url = URL(string: "http://localhost:8000/screenshot") else { return nil }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(ScreenshotResponse.self, from: data)
            
            if response.status == "success", let base64String = response.image {
                if let imageData = Data(base64Encoded: base64String) {
                    return UIImage(data: imageData)
                }
            }
        } catch {
            print("Network request failed: \(error)")
        }
        return nil
    }
}

