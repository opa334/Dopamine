//
//  AboutView.swift
//  Fugu15
//
//  Created by Linus Henze on 2022-07-29.
//

import SwiftUI

struct AboutView: View {
    @Environment(\.openURL) var openURL
    
    @State private var descriptionMaxWidth: CGFloat?
    
    struct DescriptionWidthPreferenceKey: PreferenceKey {
        static let defaultValue: CGFloat = 0

        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }
    
    var body: some View {
        VStack(alignment: .center) {
            Image("FuguIcon")
                .resizable()
                .cornerRadius(22.37)
                .padding()
                .aspectRatio(contentMode: .fit)
                .frame(width: UIScreen.main.bounds.size.width/3)
                .shadow(radius: 10)
            
            HStack(alignment: .center) {
                VStack(alignment: .leading) {
                    Text("Fugu15 Jailbreak Tool")
                        .font(.largeTitle)
                        .fontWeight(.heavy)
                        .foregroundColor(.accentColor)
                        .background(
                            GeometryReader(content: { geometry in
                                Color.clear.preference(
                                    key: DescriptionWidthPreferenceKey.self,
                                    value: geometry.size.width
                                )
                            })
                        )
                        .padding(.bottom)
                    
                    Text("Fugu15 is an (incomplete) Jailbreak for iOS 15.0 - 15.4.1, supporting iPhone XS and newer.")
                        .multilineTextAlignment(.center)
                        .frame(width: descriptionMaxWidth)
                }
                    .onPreferenceChange(DescriptionWidthPreferenceKey.self) {
                        descriptionMaxWidth = $0
                    }
            }.padding(.bottom)
            
            //
            // You should change the links below if you make any changes to Fugu15
            // so that others know where to find the source code
            //
            Link("Source Code", destination: URL(string: "https://github.com/pinauten/Fugu15")!)
                .padding([.top, .leading, .trailing])
            Link("License", destination: URL(string: "https://github.com/pinauten/Fugu15/LICENSE")!)
                .padding([.top, .leading, .trailing])
            Link("Credits", destination: URL(string: "https://github.com/pinauten/Fugu15/blob/master/README.md#Credits")!)
                .padding([.top, .leading, .trailing])
            
            Spacer()
            
            Group {
                Image("PinautenLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(.leading, 100)
                    .padding(.trailing, 100)
                    .padding(.bottom)
                    .frame(maxHeight: 100)
                    .onTapGesture {
                        openURL(URL(string: "https://pinauten.de/")!)
                    }
            }.padding(.bottom, 25)
        }
    }
}

struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        AboutView()
    }
}
