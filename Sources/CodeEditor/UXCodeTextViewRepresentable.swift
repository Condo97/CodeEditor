//
//  UXCodeTextViewRepresentable.swift
//  CodeEditor
//
//  Created by Helge Heß.
//  Copyright © 2021-2023 ZeeZide GmbH. All rights reserved.
//

import SwiftUI

#if os(macOS)
  typealias UXViewRepresentable = NSViewRepresentable
#else
  typealias UXViewRepresentable = UIViewRepresentable
#endif

struct UXCodeTextViewRepresentable : UXViewRepresentable {

  public init(source      : Binding<String>,
              selection   : Binding<Range<String.Index>>,
              language    : CodeEditor.Language?,
              theme       : CodeEditor.ThemeName,
              fontSize    : Binding<CGFloat?>,
              flags       : CodeEditor.Flags,
              indentStyle : CodeEditor.IndentStyle,
              autoPairs   : [ String : String ],
              inset       : CGSize,
              allowsUndo  : Bool,
              autoscroll  : Bool)
  {
    self._source      = source
    self._selection   = selection
    self._fontSize    = fontSize
    self.language    = language
    self.themeName   = theme
    self.flags       = flags
    self.indentStyle = indentStyle
    self.autoPairs   = autoPairs
    self.inset       = inset
    self.allowsUndo  = allowsUndo
    self.autoscroll  = autoscroll
  }
    
  @Binding private var source      : String
  @Binding private var selection   : Range<String.Index>
  @Binding private var fontSize    : CGFloat?
  @State private var language    : CodeEditor.Language?
  @State private var themeName   : CodeEditor.ThemeName
  @State private var flags       : CodeEditor.Flags
  @State private var indentStyle : CodeEditor.IndentStyle
  @State private var inset       : CGSize
  @State private var allowsUndo: Bool
  @State private var autoPairs   : [ String : String ]
  @State private var autoscroll  : Bool

  @State private var isCurrentlyUpdatingView = ReferenceTypeBool(value: false)
  
  public final class Coordinator: NSObject, UXCodeTextViewDelegate {

    @Binding var source: String
    @Binding var selection: Range<String.Index>
    @Binding var fontSize: CGFloat?
    private var isCurrentlyUpdatingView: ReferenceTypeBool
    var flags: CodeEditor.Flags

    init(source: Binding<String>, selection: Binding<Range<String.Index>>, fontSize: Binding<CGFloat?>, isCurrentlyUpdatingView: ReferenceTypeBool, flags: CodeEditor.Flags) {
      self._source = source
      self._selection = selection
      self._fontSize = fontSize
      self.isCurrentlyUpdatingView = isCurrentlyUpdatingView
      self.flags = flags
    }
    
    #if os(macOS)
      public func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? UXTextView else {
          assertionFailure("unexpected notification object")
          return
        }
        textViewDidChange(textView: textView)
      }
    #elseif os(iOS) || os(visionOS)
      public func textViewDidChange(_ textView: UITextView) {
        textViewDidChange(textView: textView)
      }
    #else
      #error("Unsupported OS")
    #endif
      
    private func textViewDidChange(textView: UXTextView) {
      guard !isCurrentlyUpdatingView.value else {
        return
      }
      if source != textView.string {
          _source.wrappedValue = textView.string
      }
    }

    #if os(macOS)
      public func textViewDidChangeSelection(_ notification: Notification) {
        guard let textView = notification.object as? UXTextView else {
          assertionFailure("unexpected notification object")
          return
        }

        textViewDidChangeSelection(textView: textView as! UXCodeTextView)
      }
    #elseif os(iOS) || os(visionOS)
      public func textViewDidChangeSelection(_ textView: UITextView) {
        textViewDidChangeSelection(textView: textView as! UXCodeTextView)
      }
    #else
      #error("Unsupported OS")
    #endif
      
    private func textViewDidChangeSelection(textView: UXCodeTextView) {
      guard !isCurrentlyUpdatingView.value else {
        return
      }
      
      let range = textView.swiftSelectedRange

      if selection != range {
        selection = range
      }
    }
      
    var allowCopy: Bool {
      return flags.contains(.selectable)
          || flags.contains(.editable)
    }
  }
  
  public func makeCoordinator() -> Coordinator {
    return Coordinator(
        source: $source,
        selection: $selection,
        fontSize: $fontSize,
        isCurrentlyUpdatingView: isCurrentlyUpdatingView,
        flags: flags)
  }

  private func updateTextView(_ textView: UXCodeTextView) {
    isCurrentlyUpdatingView.value = true
    defer {
      isCurrentlyUpdatingView.value = false
    }
      
    if let binding = fontSize {
      textView.applyNewTheme(themeName, andFontSize: binding)
    }
    else {
      textView.applyNewTheme(themeName)
    }
    textView.language = language
    
    textView.indentStyle          = indentStyle
    textView.isSmartIndentEnabled = flags.contains(.smartIndent)
    textView.autoPairCompletion   = autoPairs

    if source != textView.string {
      if let textStorage = textView.codeTextStorage {
        textStorage.replaceCharacters(in   : NSMakeRange(0, textStorage.length),
                                      with : source)
      }
      else {
        assertionFailure("no text storage?")
        textView.string = source
      }
    }

    let range = selection
    
    if range != textView.swiftSelectedRange {
      let nsrange = NSRange(range, in: textView.string)
      #if os(macOS)
        textView.setSelectedRange(nsrange)
      #elseif os(iOS) || os(visionOS)
        textView.selectedRange = nsrange
      #else
        #error("Unsupported OS")
      #endif
      
      if autoscroll {
        textView.scrollRangeToVisible(nsrange)
      }
    }

    textView.isEditable   = flags.contains(.editable)
    textView.isSelectable = flags.contains(.selectable)
  }

  #if os(macOS)
    public func makeNSView(context: Context) -> NSScrollView {
      let textView = UXCodeTextView()
      textView.autoresizingMask   = [ .width, .height ]
      textView.delegate           = context.coordinator
      textView.allowsUndo         = allowsUndo
      textView.textContainerInset = inset

      let scrollView = NSScrollView()
      scrollView.hasVerticalScroller = true
      scrollView.documentView = textView
      
      updateTextView(textView)
      return scrollView
    }
    
    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
      guard let textView = scrollView.documentView as? UXCodeTextView else {
        assertionFailure("unexpected text view")
        return
      }
      if textView.delegate !== context.coordinator {
        textView.delegate = context.coordinator
      }
      textView.textContainerInset = inset
      updateTextView(textView)
    }
  #else // iOS etc
    private var edgeInsets: UIEdgeInsets {
      return UIEdgeInsets(
        top    : inset.height, left  : inset.width,
        bottom : inset.height, right : inset.width
      )
    }
    public func makeUIView(context: Context) -> UITextView {
      let textView = UXCodeTextView()
      textView.autoresizingMask   = [ .flexibleWidth, .flexibleHeight ]
      textView.delegate           = context.coordinator
      textView.textContainerInset = edgeInsets
      #if os(iOS)
      textView.autocapitalizationType = .none
      textView.smartDashesType = .no
      textView.autocorrectionType = .no
      textView.spellCheckingType = .no
      textView.smartQuotesType = .no
      #endif
      updateTextView(textView)
      return textView
    }
    
    public func updateUIView(_ textView: UITextView, context: Context) {
      guard let textView = textView as? UXCodeTextView else {
        assertionFailure("unexpected text view")
        return
      }
      if textView.delegate !== context.coordinator {
        textView.delegate = context.coordinator
      }
      textView.textContainerInset = edgeInsets
      updateTextView(textView)
    }
  #endif // iOS
}

extension UXCodeTextViewRepresentable {
  class ReferenceTypeBool {
    var value: Bool
      
    init(value: Bool) {
      self.value = value
    }
  }
}

struct UXCodeTextViewRepresentable_Previews: PreviewProvider {
  
  static var previews: some View {
    
    UXCodeTextViewRepresentable(source      : .constant("let a = 5"),
                                selection   : .constant("".startIndex..<"".startIndex),
                                language    : nil,
                                theme       : .pojoaque,
                                fontSize    : .constant(nil),
                                flags       : [ .selectable ],
                                indentStyle : .system,
                                autoPairs   : [:],
                                inset       : .init(width: 8, height: 8),
                                allowsUndo  : true,
                                autoscroll  : false)
      .frame(width: 200, height: 100)
    
    UXCodeTextViewRepresentable(source: .constant("let a = 5"),
                                selection   : .constant("".startIndex..<"".startIndex),
                                language    : .swift,
                                theme       : .pojoaque,
                                fontSize    : .constant(nil),
                                flags       : [ .selectable ],
                                indentStyle : .system,
                                autoPairs   : [:],
                                inset       : .init(width: 8, height: 8),
                                allowsUndo  : true,
                                autoscroll  : false)
      .frame(width: 200, height: 100)
    
    UXCodeTextViewRepresentable(
      source: .constant(
        #"""
        The quadratic formula is $-b \pm \sqrt{b^2 - 4ac} \over 2a$
        \bye
        """#
      ),
      selection   : .constant("".startIndex..<"".startIndex),
      language    : .tex,
      theme       : .pojoaque,
      fontSize    : .constant(nil),
      flags       : [ .selectable ],
      indentStyle : .system,
      autoPairs   : [:],
      inset       : .init(width: 8, height: 8),
      allowsUndo  : true,
      autoscroll  : false
    )
    .frame(width: 540, height: 200)
  }
}
