#!/usr/bin/env xcrun swift

import Foundation

/**
*  StreamReader is used for reading from files, among other things.
*  c/o Airspeed Velocity
*  http://stackoverflow.com/questions/24581517/read-a-file-url-line-by-line-in-swift
*  http://stackoverflow.com/questions/29540593/read-a-file-line-by-line-in-swift-1-2
*/
class StreamReader  {
    
    let encoding : String.Encoding
    let chunkSize : Int
    
    var fileHandle : FileHandle
    let buffer : NSMutableData
    let delimData : Data
    var atEof : Bool = false

    init?(path: String, delimiter: String = "\n", encoding : String.Encoding = .utf8, chunkSize : Int = 4096) {
        self.chunkSize = chunkSize
        self.encoding = encoding
        
        guard let fileHandle = FileHandle(forReadingAtPath: path),
            let delimData = delimiter.data(using: String.Encoding.utf8),
            let buffer = NSMutableData(capacity: chunkSize) else {
                return nil
        }
        
        self.fileHandle = fileHandle
        self.delimData = delimData
        self.buffer = buffer
        
    }
    
    deinit {
        self.close()
    }
    
    /// Return next line, or nil on EOF.
    func nextLine() -> String? {
        
        if atEof {
            return nil
        }
        
        // Read data chunks from file until a line delimiter is found:
        var range = buffer.range(of: delimData, options: [], in: NSMakeRange(0, buffer.length))
        while range.location == NSNotFound {
            let tmpData = fileHandle.readData(ofLength: chunkSize)
            if tmpData.count == 0 {
                // EOF or read error.
                atEof = true
                if buffer.length > 0 {
                    // Buffer contains last line in file (not terminated by delimiter).
                    let line = NSString(data: buffer as Data, encoding: encoding.rawValue)
                    
                    buffer.length = 0
                    return line as String?
                }
                // No more lines.
                return nil
            }
            buffer.append(tmpData)
            range = buffer.range(of: delimData, options: [], in: NSMakeRange(0, buffer.length))
        }
        
        // Convert complete line (excluding the delimiter) to a string:
        let line = NSString(data: buffer.subdata(with: NSMakeRange(0, range.location)),
            encoding: encoding.rawValue)
        // Remove line (and the delimiter) from the buffer:
        buffer.replaceBytes(in: NSMakeRange(0, range.location + range.length), withBytes: nil, length: 0)
        
        return line as String?
    }
    
    /// Start reading from the beginning of file.
    func rewind() -> Void {
        fileHandle.seek(toFileOffset: 0)
        buffer.length = 0
        atEof = false
    }
    
    /// Close the underlying file. No reading must be done after calling this method.
    func close() -> Void {
        fileHandle.closeFile()
    }
}

extension StreamReader : Sequence {
    func makeIterator() -> AnyIterator<String> {
        return AnyIterator{
            return self.nextLine()
        }
    }
}

extension String {
    func substringsMatchingPattern(_ pattern: String, options: NSRegularExpression.Options, matchGroup: Int) throws -> [String] {
        let range = NSMakeRange(0, (self as NSString).length)
        let regex = try NSRegularExpression(pattern: pattern, options: options)
        let matches = regex.matches(in: self, options: [], range: range)
        
        var output: [String] = []

        for match in matches  {
            let matchRange = match.rangeAt(matchGroup)
            let matchString = (self as NSString).substring(with: matchRange)
            output.append(matchString as String)
        }
        
        return output
    }
    
    func matchesPattern(_ pattern: String, options: NSRegularExpression.Options) throws -> Bool {
        let range = NSMakeRange(0, (self as NSString).length)
        let regex = try NSRegularExpression(pattern: pattern, options: options)
        let matches = regex.firstMatch(in: self, options: [], range: range)
        
        if matches == nil {
            return false
        } else {
            return true
        }
    }
    
    func subrangesMatchingPattern(_ pattern: String, options: NSRegularExpression.Options) throws -> [NSRange] {
        let range = NSMakeRange(0, (self as NSString).length)
        let regex = try NSRegularExpression(pattern: pattern, options: options)
        let matches = regex.matches(in: self, options: [], range: range)
        return matches.map { return $0.rangeAt(0) }
    }
    
   func strip(from char:Character) -> String {
        let c = self.characters
        if let ix = c.index(of: char) {
            return String(c.prefix(upTo: ix))
        }
        return ""
    }
}

struct Playdown {
    
    var streamReaders: [(reader: StreamReader, name: String)] = []
    var playgroundDirectory = ""
    let SingleLineTextBeginningPattern = "^//:"
    let MultilineTextBeginningPattern = "/\\*:"
    let MultilineTextEndingPattern = "\\*/"
    let MarkdownCodeStartDelimiter = "```swift"
    let MarkdownCodeEndDelimiter = "```\n"

    enum LineType {
        case singleLineText, multilineText, swiftCode
    }
    
    init(filename: String) {
        
        let fileManager = FileManager.default
        let path =  fileManager.currentDirectoryPath + "/" + filename + "/Pages/"
        let playgroundPath = filename.strip(from: ".")
        playgroundDirectory =  playgroundPath.strip(from: "/")
        
        if let pathUrl = URL(string: path) {
            
            do {
                
                let directoryContents = try FileManager.default.contentsOfDirectory(at: pathUrl, includingPropertiesForKeys: nil, options: [])
                
                for element in directoryContents {
                    
                    if let pageName = element.pathComponents.last?.strip(from: ".") {
                        
                        if let streamReader = StreamReader(path: "\(filename)/Pages/\(pageName).xcplaygroundpage/Contents.swift") {
                
                            streamReaders.append((reader: streamReader, name: pageName))
                
                        }
                    }
                }
                
            } catch {
                
                let playgroundName = playgroundPath.replacingOccurrences(of: playgroundDirectory + "/", with: "")
                
                if let streamReader = StreamReader(path: "\(filename)/Contents.swift") {
                    
                    streamReaders.append((reader: streamReader, name: playgroundName))
                    
                }
            }
        }
        
    }
    
    func markdown() throws {
        
        for streamReader in streamReaders {
            
            do {
                try self.markdown(streamReader: streamReader)
            } catch {
                print(error)
            }
        }
        
    }
    
    func markdown(streamReader: (reader: StreamReader, name: String)) throws {
        var lineState: LineType = .swiftCode
        var previousLineState: LineType? = nil
        let options = NSRegularExpression.Options.allowCommentsAndWhitespace
        var fileText: String = ""
        
        for line in streamReader.reader {
            
            let singleLineBeginning = try line.matchesPattern(SingleLineTextBeginningPattern, options: options)
            let multiLineBeginning = try line.matchesPattern(MultilineTextBeginningPattern, options: options)
            let multiLineEnding = try line.matchesPattern(MultilineTextEndingPattern, options: options)
            
            // Switch into a regular-text line if necessary
            if singleLineBeginning  {
                lineState = .singleLineText
            } else if multiLineBeginning {
                lineState = .multilineText
            } else if lineState == .multilineText {
                lineState = .multilineText
            } else {
                lineState = .swiftCode
            }
            
            var outputText: String = ""
            
            if previousLineState == nil {
                // This is the first line
                
                switch lineState {
                case .singleLineText:
                    outputText = stringByStrippingSingleLineTextMetacharactersFromString(line)
                case .multilineText:
                    // The first line of a multiline comment is never displayed (it's an optional comment)
                    outputText = "" // stringByStrippingSingleLineTextMetacharactersFromString(line)
                default:
                    if !singleLineBeginning && !multiLineBeginning {
                        outputText = try stringByAlteringCodeFencing(line)
                    } else {
                        outputText = line
                    }
                }
            } else {
                // This is a regular line
                // Old state -> Current state
                
                switch (previousLineState!, lineState) {
                // Swift code -> Other
                case (.swiftCode, .swiftCode):
                    outputText = line
                case (.swiftCode, .singleLineText):
                    outputText = MarkdownCodeEndDelimiter + stringByStrippingSingleLineTextMetacharactersFromString(line)
                case (.swiftCode, .multilineText):
                    // The first line of a multiline comment is never displayed (it's an optional comment)
                    outputText = MarkdownCodeEndDelimiter + "" // stringByStrippingMultilineTextMetacharactersFromString(line)
                
                // Single line -> Other
                case (.singleLineText, .swiftCode):
                    outputText = try stringByAlteringCodeFencing(line)
                case (.singleLineText, .singleLineText):
                    outputText = stringByStrippingSingleLineTextMetacharactersFromString(line)
                case (.singleLineText, .multilineText):
                    // The first line of a multiline comment is never displayed (it's an optional comment)
                    outputText = "" // stringByStrippingMultilineTextMetacharactersFromString(line)
                    
                // Multiline -> Other
                case (.multilineText, .swiftCode):
                    outputText = try stringByAlteringCodeFencing(line)
                case (.multilineText, .singleLineText):
                    outputText = stringByStrippingSingleLineTextMetacharactersFromString(line)
                case (.multilineText, .multilineText):
                    outputText = stringByStrippingMultilineTextMetacharactersFromString(line)
                }
                
            }
            
            fileText += "\n\(outputText)"
            
            previousLineState = lineState
            
            // Handle switching out of modes
            if multiLineEnding {
                // Only handle multi-line ending if we were previously in multiline mode
                if let previous = previousLineState , previous == .multilineText {
                    previousLineState = .multilineText
                    lineState = .swiftCode
                }
            }
        }
        
        
        let markdownName = "/\(streamReader.name).markdown"
        let fileManager = FileManager.default
        let path = fileManager.currentDirectoryPath + "/" + playgroundDirectory + "/" + markdownName
        
        // Handle the closing tags
        if lineState == .swiftCode && previousLineState == .swiftCode {
            fileText += "\n\(MarkdownCodeEndDelimiter)"
        }
        
        do {
            try fileText.write(toFile: path, atomically: true, encoding: String.Encoding.utf8)
        } catch {
            print(error)
        }
    }
    
    func stringByStrippingSingleLineTextMetacharactersFromString(_ string: String) -> String {
        return string.replacingOccurrences(of: "//: ", with: "")
    }
    
    func stringByStrippingMultilineTextMetacharactersFromString(_ string: String) -> String {
        let strippedLine = string.replacingOccurrences(of: "/*:", with: "")
                                 .replacingOccurrences(of: "*/", with: "")
        return strippedLine
    }
    
    func stringByAlteringCodeFencing(_ string: String) throws -> String {
        let outputText: String
        
        // Add a newline between the markdown delimiter if necessary
        if try string.matchesPattern("\\n", options: []) || (string as NSString).length == 0 {
            // Empty line
            outputText = "\n" + MarkdownCodeStartDelimiter + string
        } else {
            outputText = MarkdownCodeStartDelimiter + "\n" + string
        }
        
        return outputText
    }
}

enum CustomError: Error {
    case FilenameRequired
}

struct Main {
    init() throws {
        if CommandLine.arguments.count < 2 {
            throw CustomError.FilenameRequired
        }

        let filename = CommandLine.arguments[1]
        let playdown = Playdown(filename: filename)
        try playdown.markdown()
    }
}

do {
    let _ = try Main()
} catch {
    print(error)
    exit(1)
}
