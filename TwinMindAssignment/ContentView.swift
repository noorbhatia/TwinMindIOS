//
//  ContentView.swift
//  TwinMindAssignment
//
//  Created by Noor Bhatia on 08/07/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        ServiceInitializationView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Session.self, inMemory: true)
}
