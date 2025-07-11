import SwiftUI

/// SwiftUI component for displaying error alerts with user-friendly messages and actions
struct ErrorAlert: View {
    let error: ErrorManager.AppError
    let errorManager: ErrorManager
    let onDismiss: () -> Void
    let onRetry: (() -> Void)?
    
    init(error: ErrorManager.AppError, errorManager: ErrorManager, onDismiss: @escaping () -> Void, onRetry: (() -> Void)? = nil) {
        self.error = error
        self.errorManager = errorManager
        self.onDismiss = onDismiss
        self.onRetry = onRetry
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Error Icon
            errorIcon
                .font(.system(size: 60))
                .foregroundColor(errorColor)
            
            // Error Message
            VStack(spacing: 12) {
                Text(errorTitle)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                
                Text(errorManager.getErrorMessage(for: error))
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Suggested Action
            VStack(spacing: 8) {
                Text("Suggested Action:")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Text(errorManager.getSuggestedAction(for: error))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            // Action Buttons
            HStack(spacing: 16) {
                // Dismiss Button
                Button(action: onDismiss) {
                    Text("Dismiss")
                        .font(.body)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .cornerRadius(12)
                }
                
                // Action Button (Settings or Retry)
                actionButton
            }
        }
        .padding(24)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        .padding(.horizontal, 20)
    }
    
    private var errorIcon: Image {
        switch error {
        case .audio:
            return Image(systemName: "mic.slash")
        case .transcription:
            return Image(systemName: "text.bubble.fill")
        case .storage:
            return Image(systemName: "externaldrive.fill.trianglebadge.exclamationmark")
        case .network:
            return Image(systemName: "wifi.exclamationmark")
        case .permission:
            return Image(systemName: "hand.raised.fill")
        case .system:
            return Image(systemName: "exclamationmark.triangle.fill")
        case .data:
            return Image(systemName: "cylinder.fill.badge.xmark")
        }
    }
    
    private var errorColor: Color {
        switch error {
        case .audio, .permission:
            return .orange
        case .transcription, .network:
            return .blue
        case .storage, .data:
            return .red
        case .system:
            return .purple
        }
    }
    
    private var errorTitle: String {
        switch error {
        case .audio:
            return "Audio Recording Issue"
        case .transcription:
            return "Transcription Problem"
        case .storage:
            return "Storage Issue"
        case .network:
            return "Network Problem"
        case .permission:
            return "Permission Required"
        case .system:
            return "System Issue"
        case .data:
            return "Data Error"
        }
    }
    
    @ViewBuilder
    private var actionButton: some View {
        if requiresSettingsAction {
            Button(action: openSettings) {
                HStack {
                    Image(systemName: "gear")
                    Text("Settings")
                }
                .font(.body)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(errorColor)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
        } else if let retryAction = onRetry {
            Button(action: retryAction) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                }
                .font(.body)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(errorColor)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
        } else {
            Button(action: onDismiss) {
                Text("OK")
                    .font(.body)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(errorColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
    }
    
    private var requiresSettingsAction: Bool {
        switch error {
        case .permission:
            return true
        case .audio(let audioError):
            return audioError == .microphonePermissionDenied
        case .transcription(let transcriptionError):
            return transcriptionError == .apiKeyMissing || transcriptionError == .speechRecognitionPermissionDenied
        default:
            return false
        }
    }
    
    private func openSettings() {
        onDismiss()
        
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
        }
    }
}

/// View modifier to automatically show error alerts
struct ErrorAlertModifier: ViewModifier {
    @ObservedObject var errorManager: ErrorManager
    let onRetry: (() -> Void)?
    
    func body(content: Content) -> some View {
        content
            .overlay(
                ZStack {
                    if errorManager.isShowingErrorAlert, let error = errorManager.currentError {
                        // Background overlay
                        Color.black.opacity(0.4)
                            .edgesIgnoringSafeArea(.all)
                            .transition(.opacity)
                        
                        // Error alert
                        ErrorAlert(
                            error: error,
                            errorManager: errorManager,
                            onDismiss: {
                                withAnimation {
                                    errorManager.clearError()
                                }
                            },
                            onRetry: onRetry
                        )
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: errorManager.isShowingErrorAlert)
            )
    }
}

/// Extension to easily add error handling to any view
extension View {
    func errorAlert(_ errorManager: ErrorManager, onRetry: (() -> Void)? = nil) -> some View {
        modifier(ErrorAlertModifier(errorManager: errorManager, onRetry: onRetry))
    }
}

/// Toast-style error notification for minor errors
struct ErrorToast: View {
    let message: String
    let type: ToastType
    @Binding var isShowing: Bool
    
    enum ToastType {
        case warning, error, info
        
        var color: Color {
            switch self {
            case .warning: return .orange
            case .error: return .red
            case .info: return .blue
            }
        }
        
        var icon: String {
            switch self {
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.circle.fill"
            case .info: return "info.circle.fill"
            }
        }
    }
    
    var body: some View {
        if isShowing {
            HStack(spacing: 12) {
                Image(systemName: type.icon)
                    .foregroundColor(type.color)
                
                Text(message)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                Spacer()
                
                Button(action: { isShowing = false }) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
            .padding(.horizontal, 20)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onAppear {
                // Auto-dismiss after 5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    withAnimation {
                        isShowing = false
                    }
                }
            }
        }
    }
}

/// Toast modifier for showing temporary error messages
struct ErrorToastModifier: ViewModifier {
    @Binding var isShowing: Bool
    let message: String
    let type: ErrorToast.ToastType
    
    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content
            
            VStack {
                ErrorToast(message: message, type: type, isShowing: $isShowing)
                Spacer()
            }
            .animation(.spring(), value: isShowing)
        }
    }
}

extension View {
    func errorToast(_ message: String, type: ErrorToast.ToastType = .error, isShowing: Binding<Bool>) -> some View {
        modifier(ErrorToastModifier(isShowing: isShowing, message: message, type: type))
    }
}

#Preview {
    VStack {
        Text("Sample Content")
            .padding()
        
        Spacer()
    }
    .errorAlert(ErrorManager())
} 
