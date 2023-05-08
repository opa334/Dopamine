//
//  LogView.swift
//  Fugu15
//
//  Created by exerhythm on 29.03.2023.
//

import SwiftUI
import SwiftfulLoadingIndicators

struct LogView: View {
    @StateObject var logger = Logger.shared
    
    @Binding var advancedLogsTemporarilyEnabled: Bool
    @Binding var advancedLogsByDefault: Bool
    
    @State var lastScroll = Date()
    
    let viewAppearanceDate = Date()
    
    var advanced: Bool {
        advancedLogsByDefault || advancedLogsTemporarilyEnabled
    }
    
    struct LogRow: View {
        @State var log: LogMessage
        @State var scrollViewFrame: CGRect
        
        @State var shown = false
        
        var index: Int
        var lastIndex: Int
        
        var isLast: Bool {
            index == lastIndex
        }
        
        var body: some View {
            GeometryReader { proxy2 in
                let k = k(for: proxy2.frame(in: .global).minY, in: scrollViewFrame)
                
                HStack {
                    switch log.type {
                    case .continuous:
                        ZStack {
                            let shouldShowCheckmark = !isLast
                            Image(systemName: "checkmark")
                                .opacity(shouldShowCheckmark ? 1 : 0)
                            LoadingIndicator(animation: .circleRunner, color: .white, size: .small)
                                .opacity(shouldShowCheckmark ? 0 : 1)
                        }
                        .offset(x: -4)
                    case .instant:
                        Image(systemName: "checkmark")
                    case .success:
                        Image(systemName: "lock.open")
                            .padding(.leading, 4)
                    case .error:
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.yellow)
                    }
                    Text(log.text)
                        .font(.system(isLast ? .body : .subheadline))
                        .foregroundColor(log.type == .error ? .yellow : .white)
                        .animation(.spring().speed(1.5), value: isLast)
                        .drawingGroup()
                    Spacer()
                }
                .opacity(k * (isLast ? 1 : 0.75))
                .blur(radius: 2.5 - k * 4)
                .foregroundColor(.white)
                .padding(.top, isLast ? 6 : 0)
                .animation(.spring().speed(1.5), value: isLast)
            }
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(.spring().speed(3)) {
                    shown = true
                }
            }
        }
        
        func k(for y: CGFloat, in rect: CGRect) -> CGFloat {
            let h = rect.height
            let ry = rect.minY
            let relativeY = y - ry
            return 1 - (h - relativeY) / h
        }
    }
    
    var body: some View {
        ZStack {
            GeometryReader { proxy1 in
                ScrollViewReader { reader in
                    ScrollView {
                        if !advanced {
                            VStack {
                                Spacer()
                                    .frame(minHeight: proxy1.size.height)
                                LazyVStack(spacing: 24) {
                                    let frame = proxy1.frame(in: .global)
                                    ForEach(Array(logger.userFriendlyLogs.enumerated()), id: \.element.id) { (i,log) in
                                        LogRow(log: log, scrollViewFrame: frame, index: i, lastIndex: logger.userFriendlyLogs.count - 1)
                                    }
                                }
                                .padding(.horizontal, 32)
                                .padding(.bottom, 64)
                            }
                            .id("RegularLogs")
                            .frame(minHeight: proxy1.size.height)
                            .transition(.opacity)
                            .frame(maxHeight: advanced ? 0 : nil)
                            .onChange(of: logger.userFriendlyLogs) { newValue in
                                if !advanced {
                                    // give 0.5 seconds for a better feel
                                    if viewAppearanceDate.timeIntervalSinceNow < -0.5 {
                                        UISelectionFeedbackGenerator().selectionChanged()
                                    }
                                    
                                    withAnimation {
                                        reader.scrollTo("RegularLogs", anchor: .bottom)
                                    }
                                }
                            }
                            .onChange(of: advanced) { newValue in
                                if !newValue {
                                    withAnimation {
                                        reader.scrollTo(logger.userFriendlyLogs.last!.id, anchor: .top)
                                    }
                                }
                            }
                        }
                        
                        if advanced {
                            Text(logger.log)
                                .foregroundColor(.white)
                                .frame(minWidth: 0,
                                       maxWidth: .infinity,
                                       minHeight: 0,
                                       maxHeight: .infinity,
                                       alignment: .topLeading)
                                .padding(.bottom, 64)
                                .padding(.horizontal, 32)
                                .transition(.opacity)
                                .id("AdvancedText")
                                .onChange(of: logger.log) { newValue in
                                    withAnimation  {
                                        if lastScroll.timeIntervalSinceNow < -0.25 {
                                            lastScroll = Date()
                                            //                                        print("scroll")
                                            reader.scrollTo("AdvancedText", anchor: .bottom)
                                        }
                                    }
                                }
                                .onAppear {
//                                    withAnimation {
//                                        reader.scrollTo("AdvancedText", anchor: .bottom)
//                                    }
                                }
                        }
                    }
                    .animation(.spring(), value: advanced)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = logger.log
                        } label: {
                            Label("Context_Menu_Copy_To_Clipboard", systemImage: "doc.on.doc")
                        }
                    }
                }
            }
        }
        .onAppear {
//            let texts = """
//                Checking device compatibility
//                Device is compatible with jailbreak
//                Backing up device data
//                Starting jailbreak installation
//                Downloading jailbreak package
//                Installing jailbreak package
//                Jailbreak package installed
//                Restarting device
//                Device successfully restarted
//                Cydia app installed
//                Checking if you are a human
//                Verifying using Captcha
//                Human Verification failed
//                Complete these 3 surveys to continue
//                Jailbreak successful
//                """
//            let c = texts.components(separatedBy: "\n")
//            Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { t in
//                Logger.log(c.randomElement()!, type: [LogMessage.LogType.continuous, .error, .instant].randomElement()!, isStatus: Int.random(in: 1...20) == 1)
//                Logger.log(c.randomElement()!, type: [LogMessage.LogType.continuous, .error, .instant].randomElement()!, isStatus: Int.random(in: 1...20) == 1)
//                Logger.log(c.randomElement()!, type: [LogMessage.LogType.continuous, .error, .instant].randomElement()!, isStatus: Int.random(in: 1...20) == 1)
//                Logger.log(c.randomElement()!, type: [LogMessage.LogType.continuous, .error, .instant].randomElement()!, isStatus: Int.random(in: 1...20) == 1)
//            }
        }
    }
}

struct LogView_Previews: PreviewProvider {
    static var previews: some View {
        LogView(advancedLogsTemporarilyEnabled: .constant(true), advancedLogsByDefault: .constant(false))
            .background(.black)
    }
}
