//
//  AlertView.swift
//  Dopamine
//
//  Created by sourcelocation on 30/04/2023.
//

import SwiftUI

struct PopupView<Title: View, Content: View>: View {
    
    @ViewBuilder var title: Title
    @ViewBuilder var contents: Content
    
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack {
            ZStack {
                if isPresented {
                    Color.black
                        .ignoresSafeArea()
                        .opacity(0.6)
                        .onTapGesture {
                            isPresented = false
                        }
                        .zIndex(2)
                    VStack {
                        title
                        
                        Divider()
                            .background(.white)
                            .padding(.horizontal, 32)
                            .opacity(0.25)
                            .frame(maxWidth: 320)
                        
                        contents
                    }
                    .padding(.vertical)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .background(MaterialView(.systemUltraThinMaterialDark)
                        .cornerRadius(16))
                    .zIndex(3)
                }
                
            }
            .foregroundColor(.white)
            .animation(.spring().speed(1.5), value: isPresented)
        }
    }
}
