//
//  RichEditor.swift
//
//  Created by Caesar Wirth on 4/1/15.
//  Copyright (c) 2015 Caesar Wirth. All rights reserved.
//

import UIKit
import WebKit

/// RichEditorDelegate defines callbacks for the delegate of the RichEditorView
@objc public protocol RichEditorDelegate: class {
    
    /// Called when the inner height of the text being displayed changes
    /// Can be used to update the UI
    @objc optional func richEditor(_ editor: RichEditorView, heightDidChange height: Int)
    
    /// Called whenever the content inside the view changes
    
    @objc optional func richEditor(_ editor: RichEditorView, contentDidChange content: String)
    
    /// Called when the rich editor starts editing
    
    @objc optional func richEditorTookFocus(_ editor: RichEditorView)
    
    /// Called when the rich editor stops editing or loses focus
    
    @objc optional func richEditorLostFocus(_ editor: RichEditorView)
    
    /// Called when the RichEditorView has become ready to receive input
    /// More concretely, is called when the internal WKWebView loads for the first time, and contentHTML is set
    
    @objc optional func richEditorDidLoad(_ editor: RichEditorView)
    
    /// Called when the internal WKWebView begins loading a URL that it does not know how to respond to
    /// For example, if there is an external link, and then the user taps it
    
    @objc optional func richEditor(_ editor: RichEditorView, shouldInteractWith url: URL) -> Bool
    
    /// Called when custom actions are called by callbacks in the JS
    /// By default, this method is not used unless called by some custom JS that you add
    
    @objc optional func richEditor(_ editor: RichEditorView, handle action: String)
}

/// RichEditorView is a UIView that displays richly styled text, and allows it to be edited in a WYSIWYG fashion.

@objcMembers open class RichEditorView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate, WKURLSchemeHandler {
    
    
    
    // MARK: Public Properties
    
    /// The delegate that will receive callbacks when certain actions are completed.
    open weak var delegate: RichEditorDelegate?
    var task: WKURLSchemeTask?
    
    /// Input accessory view to display over they keyboard.
    /// Defaults to nil
    open override var inputAccessoryView: UIView? {
        get { return webView.accessoryView }
        set {webView.accessoryView = newValue}
        
    }
    
    /// The internal WKWebView that is used to display the text.
    open private(set) var webView: RichEditorWebView
    
    /// Whether or not scroll is enabled on the view.
    open var isScrollEnabled: Bool = true {
        didSet {
            webView.scrollView.isScrollEnabled = isScrollEnabled
        }
    }
    
    /// Whether or not to allow user input in the view.
    open var isEditingEnabled: Bool {
        get { return isContentEditable }
        set { isContentEditable = newValue }
    }
    
    /// The content HTML of the text being displayed.
    /// Is continually updated as the text is being edited.
    open private(set) var contentHTML: String = "" {
        didSet {
            delegate?.richEditor?(self, contentDidChange: contentHTML)
        }
    }
    
    /// The internal height of the text being displayed.
    /// Is continually being updated as the text is edited.
    open private(set) var editorHeight: Int = 0 {
        didSet {
            delegate?.richEditor?(self, heightDidChange: editorHeight)
        }
    }
    
    /// The value we hold in order to be able to set the line height before the JS completely loads.
    private var innerLineHeight: Int = 28
    
    /// The line height of the editor. Defaults to 28.
    open private(set) var lineHeight: Int = 28 {
        didSet {
            innerLineHeight = lineHeight
            webView.evaluateJavaScript("RE.setLineHeight('\(innerLineHeight)px');") {  (response: Any?, error: Error?) in
                
            }
        }
    }
    
    func getLineHeight(onCompletion:@escaping((Int, Error?)-> Void)) {
        guard isEditorLoaded == true else {return onCompletion(innerLineHeight , nil)}
        webView.evaluateJavaScript("RE.getLineHeight();", completionHandler: { (response: Any?, error: Error?) in
            if let intResponse = response as? Int {
                onCompletion(intResponse, error)
            } else {
                onCompletion(self.lineHeight, error)
            }
        })
        
        
    }
    
    // MARK: Private Properties
    
    /// Whether or not the editor has finished loading or not yet.
    private var isEditorLoaded = false
    
    /// Value that stores whether or not the content should be editable when the editor is loaded.
    /// Is basically `isEditingEnabled` before the editor is loaded.
    private var editingEnabledVar = true
    
    /// The private internal tap gesture recognizer used to detect taps and focus the editor
    private let tapRecognizer = UITapGestureRecognizer()
    
    /// The inner height of the editor div.
    /// Fetches it from JS every time, so might be slow!
    func getClientHeight(onCompletion:@escaping((Int, Error?)-> Void)) {
        webView.evaluateJavaScript("document.body.scrollHeight;", completionHandler: { (response: Any?, error: Error?) in
            if let intResponse = response as? Int {
                onCompletion(intResponse, error)
            } else {
                onCompletion(0, error)
            }
        })
    }
    
    
    // MARK: Initialization
    
    public override init(frame: CGRect) {
        webView = RichEditorWebView()
        super.init(frame: frame)
        setup()
    }
    
    required public init?(coder aDecoder: NSCoder) {
        // The Javascript source need to be injected at initialization with the initial configuration
        let webConfig = WKWebViewConfiguration()
        if let filePath = Bundle(for: RichEditorView.self).path(forResource: "rich_editor", ofType: "js"),
            let scriptContent = try? String(contentsOfFile: filePath, encoding: String.Encoding.utf8) {
            webConfig.userContentController.addUserScript(
                WKUserScript(source: scriptContent,
                             injectionTime: .atDocumentEnd,
                             forMainFrameOnly: false
                )
            )
        }
        
        let schemeHandler = RichEditorSchemeHandler()
        webConfig.setURLSchemeHandler(schemeHandler, forURLScheme: schemeHandler.kURLScheme)
        webView = RichEditorWebView(frame: CGRect.zero, configuration: webConfig)
        super.init(coder: aDecoder)
        
        setup()
    }
    
    private func setup() {
        backgroundColor = .white
        
        webView.frame = bounds
        webView.navigationDelegate = self
        //webView.keyboardDisplayRequiresUserAction = false
        //webView.scalesPageToFit = false
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        //webView.dataDetectorTypes = UIDataDetectorTypes()
        webView.configuration.userContentController.add(self, name:"postascript")
        
        // These to are a fix for a bug where (old web view) would display a black line at the bottom of the view.
        // https://stackoverflow.com/questions/21420137/black-line-appearing-at-bottom-of-uiwebview-how-to-remove
        webView.backgroundColor = .clear
        webView.isOpaque = false
        
        webView.scrollView.isScrollEnabled = isScrollEnabled
        webView.scrollView.bounces = false
        webView.scrollView.delegate = self
        webView.scrollView.clipsToBounds = false
        
        
        
        self.addSubview(webView)
        
        if let filePath = Bundle(for: RichEditorView.self).path(forResource: "rich_editor", ofType: "html") {
            let url = URL(fileURLWithPath: filePath, isDirectory: false)
            
            if #available(iOS 9.0, *) {
                let cacheDirectoryURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                webView.loadFileURL(url, allowingReadAccessTo: cacheDirectoryURL)
            } else {
                // Fallback on earlier versions
                
            }
            let request = URLRequest(url: url)
            webView.load(request)
        }
        
        tapRecognizer.addTarget(self, action: #selector(viewWasTapped))
        tapRecognizer.delegate = self
        addGestureRecognizer(tapRecognizer)
    }
    
    // MARK: - Rich Text Editing
    
    // MARK: Properties
    
    /// The HTML that is currently loaded in the editor view, if it is loaded. If it has not been loaded yet, it is the
    /// HTML that will be loaded into the editor view once it finishes initializing.
    public var html: String = String() {
        didSet {
            contentHTML = html
            if isEditorLoaded {
                runJSX("RE.setHtml('\(html.escaped)');") { (response: String, error: Error?) in
                    self.updateHeight()
                }
            }
        }
    }
    
    public func getHtml(onCompletion:@escaping((String, Error?)-> Void)) {
        runJSX("RE.getHtml();") { (response:String, error: Error?) in
            guard error == nil else {
                onCompletion(String(), error)
                return
            }
            onCompletion(response, nil)
        }
    }
    
    /// Text representation of the data that has been input into the editor view, if it has been loaded.
    public var text: String {
        return runJS("RE.getText()")
    }
    
    /// Private variable that holds the placeholder text, so you can set the placeholder before the editor loads.
    private var placeholderText: String = ""
    /// The placeholder text that should be shown when there is no user input.
    open var placeholder: String {
        get { return placeholderText }
        set {
            placeholderText = newValue
            runJS("RE.setPlaceholderText('\(newValue.escaped)');")
        }
    }
    
    
    /// The href of the current selection, if the current selection's parent is an anchor tag.
    /// Will be nil if there is no href, or it is an empty string.
    public var selectedHref: String? {
        if !hasRangeSelection { return nil }
        let href = runJS("RE.getSelectedHref();")
        if href == "" {
            return nil
        } else {
            return href
        }
    }
    
    /// Whether or not the selection has a type specifically of "Range".
    public var hasRangeSelection: Bool {
        return runJS("RE.rangeSelectionExists();") == "true" ? true : false
    }
    
    /// Whether or not the selection has a type specifically of "Range" or "Caret".
    public var hasRangeOrCaretSelection: Bool {
        return runJS("RE.rangeOrCaretSelectionExists();") == "true" ? true : false
    }
    
    // MARK: Methods
    
    public func removeFormat() {
        runJS("RE.removeFormat();")
    }
    
    public func setFontSize(_ size: Int) {
        runJS("RE.setFontSize('\(size)px');")
    }
    
    public func setEditorBackgroundColor(_ color: UIColor) {
        runJS("RE.setBackgroundColor('\(color.hex)');")
    }
    
    public func undo() {
        runJS("RE.undo();")
    }
    
    public func redo() {
        runJS("RE.redo();")
    }
    
    public func bold() {
        runJS("RE.setBold();")
    }
    
    public func italic() {
        runJS("RE.setItalic();")
    }
    
    // "superscript" is a keyword
    public func subscriptText() {
        runJS("RE.setSubscript();")
    }
    
    public func superscript() {
        runJS("RE.setSuperscript();")
    }
    
    public func strikethrough() {
        runJS("RE.setStrikeThrough();")
    }
    
    public func underline() {
        runJS("RE.setUnderline();")
    }
    
    public func setTextColor(_ color: UIColor) {
        runJS("RE.prepareInsert();")
        runJS("RE.setTextColor('\(color.hex)');")
    }
    
    public func setTextBackgroundColor(_ color: UIColor) {
        runJS("RE.prepareInsert();")
        runJS("RE.setTextBackgroundColor('\(color.hex)');")
    }
    
    public func header(_ h: Int) {
        runJS("RE.setHeading('\(h)');")
    }
    
    public func indent() {
        runJS("RE.setIndent();")
    }
    
    public func outdent() {
        runJS("RE.setOutdent();")
    }
    
    public func orderedList() {
        runJS("RE.setOrderedList();")
    }
    
    public func unorderedList() {
        runJS("RE.setUnorderedList();")
    }
    
    public func blockquote() {
        runJS("RE.setBlockquote()");
    }
    
    public func alignLeft() {
        runJS("RE.setJustifyLeft();")
    }
    
    public func alignCenter() {
        runJS("RE.setJustifyCenter();")
    }
    
    public func alignRight() {
        runJS("RE.setJustifyRight();")
    }
    
    public func insertImage(_ url: String, alt: String, width:Int = 150, height:Int = 150) {
        runJS("RE.prepareInsert();")
        runJS("RE.insertImage('\(url.escaped)', '\(alt.escaped)', \(width), \(height));")
    }
    
    public func insertLink(_ href: String, title: String) {
        runJS("RE.prepareInsert();")
        runJS("RE.insertLink('\(href.escaped)', '\(title.escaped)');")
    }
    
    public func focus() {
        runJS("RE.focus();")
    }
    
    public func focus(at: CGPoint) {
        runJS("RE.focusAtPoint(\(at.x), \(at.y));")
    }
    
    public func blur() {
        runJS("RE.blurFocus()")
    }
    
    /// Runs some JavaScript on the WKWebView. It will always return an empty string
    /// Can be used to run a JS fragment without expecting a result.
    /// If a result is need it, then runJSX will return a result on the completionHandler
    /// as long as the conversion from JS to Swift is supported (for example num will return as Int...)
    /// - parameter js: The JavaScript string to be run
    /// - returns: Empty string
    @discardableResult
    public func runJS(_ js: String) -> String {
        webView.evaluateJavaScript(js) {  (response: Any?, error: Error?) in
            
        }
        return String()
    }
    
    public func runJSX(_ js: String, onCompletion: @escaping (String, Error?) -> Void) {
        webView.evaluateJavaScript(js, completionHandler: { (response: Any?, error: Error?) in
            if let stringResponse = response as? String {
                onCompletion(stringResponse, error)
            } else {
                onCompletion(String(), error)
            }
        })
    }
    
    
    // MARK: - Delegate Methods
    
    
    // MARK: UIScrollViewDelegate
    
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // We use this to keep the scroll view from changing its offset when the keyboard comes up
        if !isScrollEnabled {
            scrollView.bounds = webView.bounds
        }
    }
    
    // MARK: UIGestureRecognizerDelegate
    
    /// Delegate method for our UITapGestureDelegate.
    /// Since the internal web view also has gesture recognizers, we have to make sure that we actually receive our taps.
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
    
    
    // MARK: - Private Implementation Details
    
    private var isContentEditable: Bool {
        get {
            if isEditorLoaded {
                let value = runJS("RE.editor.isContentEditable")
                editingEnabledVar = Bool(value) ?? false
                return editingEnabledVar
            }
            return editingEnabledVar
        }
        set {
            editingEnabledVar = newValue
            if isEditorLoaded {
                let value = newValue ? "true" : "false"
                runJS("RE.editor.contentEditable = \(value);")
            }
        }
    }
    
    /// The position of the caret relative to the currently shown content.
    /// For example, if the cursor is directly at the top of what is visible, it will return 0.
    /// This also means that it will be negative if it is above what is currently visible.
    /// Can also return 0 if some sort of error occurs between JS and here.
    private var relativeCaretYPosition: Int = 0
    func getRelativeCaretYPosition(onCompletion:@escaping((Int, Error?)-> Void)){
        webView.evaluateJavaScript("RE.getRelativeCaretYPosition();", completionHandler: { (response: Any?, error: Error?) in
            if let stringResponse = response as? Int {
                onCompletion(stringResponse, error)
            } else {
                onCompletion(0, error)
            }
        })
    }
    private func updateHeight() {
        runJSX("RE.getClientHeight()") { (heightString, error: Error?) in
            guard error == nil else {return}
            let height = Int(heightString) ?? 0
            if self.editorHeight != height {
                self.editorHeight = height
            }
        }
    }
    
    /// Scrolls the editor to a position where the caret is visible.
    /// Called repeatedly to make sure the caret is always visible when inputting text.
    /// Works only if the `lineHeight` of the editor is available.
    private func scrollCaretToVisible() {
        let scrollView = self.webView.scrollView
        
        self.getClientHeight { (clientHeight, error: Error?) in
            guard error == nil else {return}
            let contentHeight = clientHeight > 0 ? CGFloat(clientHeight) : scrollView.frame.height
            scrollView.contentSize = CGSize(width: scrollView.frame.width, height: contentHeight)
            
            // XXX: Maybe find a better way to get the cursor height
            self.getLineHeight(onCompletion: { (_lineHeight: Int, error: Error?) in
                guard error == nil else {return}
                let lineHeight = CGFloat(_lineHeight)
                let cursorHeight = lineHeight - 4
                self.getRelativeCaretYPosition(onCompletion: { (caretYPosition: Int, error: Error?) in
                    guard error == nil else {return}
                    let visiblePosition = CGFloat(caretYPosition)
                    var offset: CGPoint?
                    
                    if visiblePosition + cursorHeight > scrollView.bounds.size.height {
                        // Visible caret position goes further than our bounds
                        offset = CGPoint(x: 0, y: (visiblePosition + lineHeight) - scrollView.bounds.height + scrollView.contentOffset.y)
                        
                    } else if visiblePosition < 0 {
                        // Visible caret position is above what is currently visible
                        var amount = scrollView.contentOffset.y + visiblePosition
                        amount = amount < 0 ? 0 : amount
                        offset = CGPoint(x: scrollView.contentOffset.x, y: amount)
                        
                    }
                    
                    if let offset = offset {
                        scrollView.setContentOffset(offset, animated: false)
                    }
                })
            })
        }
        
    }
    
    /// Called when actions are received from JavaScript
    /// - parameter method: String with the name of the method and optional parameters that were passed in
    func performCommand(_ method: String) {
        if method.hasPrefix("ready") {
            // If loading for the first time, we have to set the content HTML to be displayed
            if !isEditorLoaded {
                isEditorLoaded = true
                html = contentHTML
                isContentEditable = editingEnabledVar
                placeholder = placeholderText
                lineHeight = innerLineHeight
                delegate?.richEditorDidLoad?(self) //////-> TODO: Test if required to add inside the responseClosure
            }
            updateHeight()
        }
        else if method.hasPrefix("input") {
            scrollCaretToVisible()
            self.getHtml { [weak self] (html, error) in
                
                guard error == nil else {return}
                guard let sSelf = self else {return}
                let content = html
                sSelf.contentHTML = content
                sSelf.updateHeight()
            }
            
        }
        else if method.hasPrefix("updateHeight") {
            updateHeight()
        }
        else if method.hasPrefix("focus") {
            delegate?.richEditorTookFocus?(self)
        }
        else if method.hasPrefix("blur") {
            delegate?.richEditorLostFocus?(self)
        }
        else if method.hasPrefix("action/") {
            self.getHtml { (html, error) in
                guard error == nil else {return}
                let content = html
                self.contentHTML = content
                
                // If there are any custom actions being called
                // We need to tell the delegate about it
                let actionPrefix = "action/"
                let range = method.range(of: actionPrefix)!
                let action = method.replacingCharacters(in: range, with: "")
                self.delegate?.richEditor?(self, handle: action)
            }
            
        }
    }
    
    /// Called by the UITapGestureRecognizer when the user taps the view.
    /// If we are not already the first responder, focus the editor.
    @objc private func viewWasTapped() {
        if !webView.containsFirstResponder {
            let point = tapRecognizer.location(in: webView)
            focus(at: point)
        }
    }
    
}

/**
 This is the new delegate
 */

extension RichEditorView: WKNavigationDelegate {
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        print(webView)
    }
    
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let callbackPrefix = "re-callback://"
        if navigationAction.request.url?.absoluteString.hasPrefix(callbackPrefix) == true {
            
            // When we get a callback, we need to fetch the command queue to run the commands
            // It comes in as a JSON array of commands that we need to parse
            //let commands = runJS("RE.getCommandQueue();")
            runJSX("RE.getCommandQueue();") { [weak self] (commands: String, error: Error?) in
                guard let sSelf = self else {return}
                guard error == nil else {
                    decisionHandler(.cancel)
                    return
                    
                }
                if let data = commands.data(using: .utf8) {
                    
                    let jsonCommands: [String]
                    do {
                        jsonCommands = try JSONSerialization.jsonObject(with: data) as? [String] ?? []
                    } catch {
                        jsonCommands = []
                        NSLog("RichEditorView: Failed to parse JSON Commands")
                    }
                    
                    jsonCommands.forEach(sSelf.performCommand)
                }
                
            }
            decisionHandler(.cancel)
            return
            
        }
        // User is tapping on a link, so we should react accordingly
        if navigationAction.navigationType == .linkActivated ||
            navigationAction.navigationType == .backForward {
            
            if #available(iOS 11.0, *) {
                if let url = navigationAction.request.url,
                    let shouldInteract = delegate?.richEditor?(self, shouldInteractWith: url)
                {
                    decisionHandler(.cancel)
                    return
                }
            } else {
                // Fallback on earlier versions
            }
        }
        decisionHandler(.allow)
    }
    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        print(navigation)
    }
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print(error)
    }
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print(error)
    }
    
    public func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        print(navigation)
    }
    
    public func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        print(challenge)
    }
    public func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let task = task else {return}
        if let url = urlSchemeTask.request.url, let imageData = try? Data(contentsOf: url), let image = UIImage(data: imageData) {
            if let dataRep = image.jpegData(compressionQuality: 1.0) {
                task.didReceive(URLResponse(url: task.request.url!, mimeType: "image/jpeg", expectedContentLength: dataRep.count, textEncodingName: nil))
                task.didReceive(dataRep)
                task.didFinish()
            }
        }
    }
    
    public func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        task = nil
    }
}



extension RichEditorView: WKScriptMessageHandler {
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        print(message.body)
    }
}

/*
 Overwriting the WKWebView for modifying the inputAccessoryView
 */
public class RichEditorWebView: WKWebView {
    
    public var accessoryView: UIView?
    
    public override var inputAccessoryView: UIView? {
        return accessoryView
    }
    
}

/*
 RichEditorSchemeHandler class will implement the WKURLSchemeHandler to intercept load request using the kURLScheme.
 There are problems loading local resources using WKWebView. The scheme (file:///) will have the alias of localhost:///.
 We have the control of the incomming tasks for that scheme kURLScheme. We can decide the appropiate flow.
 For now we just let them pass, so they can be injected in the html file.
 */

class RichEditorSchemeHandler: NSObject, WKURLSchemeHandler {
    var task: WKURLSchemeTask?
    var kURLScheme = "localhost"
    public func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let urlString = urlSchemeTask.request.url?.absoluteString.replacingOccurrences(of: kURLScheme, with: "file") ?? String()
        let task = urlSchemeTask
        if let url = URL(string: urlString), let imageData = try? Data(contentsOf: url), let image = UIImage(data: imageData) {
            if let dataRep = image.jpegData(compressionQuality: 1.0) {
                task.didReceive(URLResponse(url: task.request.url!, mimeType: "image/jpeg", expectedContentLength: dataRep.count, textEncodingName: nil))
                task.didReceive(dataRep)
                task.didFinish()
            }
        } else if let url = URL(string: urlString), let data = try? Data(contentsOf: url) {
            task.didReceive(URLResponse(url: task.request.url!, mimeType: nil, expectedContentLength: data.count, textEncodingName: nil))
            task.didReceive(data)
            task.didFinish()
        }
    }
    
    public func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        task = nil
    }
}



