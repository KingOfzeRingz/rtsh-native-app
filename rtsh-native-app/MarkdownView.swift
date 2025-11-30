import SwiftUI

enum MarkdownBlock: Identifiable {
    case header(level: Int, text: String)
    case codeBlock(code: String)
    case list(items: [String])
    case paragraph(text: String)
    
    var id: UUID { UUID() }
}

struct MarkdownView: View {
    let text: String
    
    var blocks: [MarkdownBlock] {
        var result: [MarkdownBlock] = []
        let lines = text.components(separatedBy: .newlines)
        var currentCodeBlock: String?
        var currentList: [String] = []
        
        for line in lines {
            // Code Block Handling
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if let code = currentCodeBlock {
                    // End of block
                    result.append(.codeBlock(code: code))
                    currentCodeBlock = nil
                } else {
                    // Start of block
                    currentCodeBlock = ""
                }
                continue
            }
            
            if let code = currentCodeBlock {
                let separator = code.isEmpty ? "" : "\n"
                currentCodeBlock = code + separator + line
                continue
            }
            
            // List Handling
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("- ") || 
               line.trimmingCharacters(in: .whitespaces).hasPrefix("* ") {
                let item = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                currentList.append(item)
                continue
            } else if !currentList.isEmpty {
                 // End of list
                result.append(.list(items: currentList))
                currentList = []
            }
            
            // Header Handling
            if line.hasPrefix("#") {
                let level = line.prefix(while: { $0 == "#" }).count
                let text = String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                result.append(.header(level: level, text: text))
                continue
            }
            
            // Paragraph Handling
            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                result.append(.paragraph(text: line))
            }
        }
        
        // Flush remaining list
        if !currentList.isEmpty {
            result.append(.list(items: currentList))
        }
        
        return result
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks) { block in
                switch block {
                case .header(let level, let text):
                    Text(text)
                        .font(fontForHeader(level))
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .padding(.top, level == 1 ? 4 : 8)
                    
                case .codeBlock(let code):
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(code)
                            .font(.system(.caption, design: .monospaced))
                            .padding()
                            .background(Color.black.opacity(0.05))
                            .cornerRadius(8)
                    }
                    
                case .list(let items):
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(items, id: \.self) { item in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                    .font(.body)
                                    .foregroundColor(.gray)
                                Text(.init(item)) // Parse inline markdown
                                    .font(.body)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.leading, 8)
                    
                case .paragraph(let text):
                    Text(.init(text)) // Parse inline markdown
                        .font(.body)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    
    func fontForHeader(_ level: Int) -> Font {
        switch level {
        case 1: return .title
        case 2: return .title2
        case 3: return .title3
        default: return .headline
        }
    }
}
