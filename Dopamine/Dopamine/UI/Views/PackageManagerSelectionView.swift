//
//  PackageManagerSelectionView.swift
//  Fugu15
//
//  Created by sourcelocation on 15/04/2023.
//

import SwiftUI

struct PackageManagerSelectionView: View {
    
    @State var selectedNames: [String] = []
    
    var onContinue: () -> Void
    
    var packageManagers: [(String, String)] = [
        ("Sileo", "Sileo"),
        ("Zebra", "Zebra")
    ]
    
    var body: some View {
        VStack {
            Spacer()
            
            HStack(spacing: 64) {
                ForEach(packageManagers.indices, id: \.self) { pmI in
                    let pm = packageManagers[pmI]
                    let name = pm.0
                    let imageName = pm.1
                    
                    Button {
                        if selectedNames.contains(name) {
                            selectedNames.removeAll(where: { $0 == name })
                        } else {
                            selectedNames.append(name)
                        }
                    } label: {
                        VStack(spacing: 12) {
                            Image(imageName)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 64)
                                .cornerRadius(14)
                            
                            HStack {
                                Text(name)
                                
                                let isSelected = selectedNames.contains(name)
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(isSelected ? .white : .white.opacity(0.5))
                            }
                        }
                    }
                }
            }
            
            Text("If you are unsure which one to select, use Sileo")
                .foregroundColor(.white.opacity(0.5))
                .padding(.vertical)
                .padding(.horizontal, 64)
                .multilineTextAlignment(.center)
            
            Spacer()
            
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onContinue()
            } label: {
                Label(title: { Text("Continue") }, icon: {
                    Image(systemName: "arrow.right")
                })
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: 280)
                .background(MaterialView(.light)
                    .opacity(0.5)
                    .cornerRadius(8)
                )
                .opacity(selectedNames.isEmpty ? 0.5 : 1)
                
            }
            .disabled(selectedNames.isEmpty)
            .animation(.spring(), value: selectedNames)
        }
        .foregroundColor(.white)
        .onChange(of: selectedNames) { newValue in
            UserDefaults.standard.set(newValue, forKey: "selectedPackageManagers")
        }
    }
}

struct PackageManagerSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Image("Wallpaper")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .edgesIgnoringSafeArea(.all)
                .blur(radius: 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Color.black
                .opacity(0.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
            PackageManagerSelectionView(onContinue: {
                
            })
                .frame(maxHeight: 300)
        }
    }
}
