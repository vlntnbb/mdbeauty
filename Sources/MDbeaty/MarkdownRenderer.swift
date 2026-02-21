import Foundation
import Ink

enum MarkdownRenderer {
    private struct HeadingCandidate {
        let level: Int
        let explicitID: String?
    }

    private struct ParsedHeadingLine {
        let level: Int
        let text: String
        let explicitID: String?
    }

    private struct TOCEntry {
        let level: Int
        let id: String
        let title: String
    }

    private struct FrontMatterExtraction {
        let frontMatter: String?
        let bodyMarkdown: String
    }

    static let welcomeHTML = """
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width,initial-scale=1">
      <style>
        :root {
          color-scheme: light dark;
          --bg: #f5f7fa;
          --card: #ffffff;
          --fg: #1f2732;
          --muted: #5b6572;
          --accent: #0f6fd6;
          --border: rgba(33, 43, 54, 0.14);
          --quote: #2f6db0;
          --code-bg: #f0f2f7;
          --shadow: 0 20px 55px rgba(10, 18, 28, 0.08);
        }
        @media (prefers-color-scheme: dark) {
          :root {
            --bg: #0f141b;
            --card: #131b24;
            --fg: #dde5ef;
            --muted: #9aa8ba;
            --accent: #66b3ff;
            --border: rgba(214, 225, 238, 0.2);
            --quote: #8ec5ff;
            --code-bg: #1a2430;
            --shadow: 0 26px 68px rgba(0, 0, 0, 0.35);
          }
        }
        html, body {
          margin: 0;
          min-height: 100%;
          background:
            radial-gradient(circle at 14% 14%, rgba(96, 153, 224, 0.16), transparent 44%),
            radial-gradient(circle at 86% 12%, rgba(35, 140, 191, 0.11), transparent 38%),
            var(--bg);
          color: var(--fg);
          font-family: "Avenir Next", "Charter", "Iowan Old Style", serif;
        }
        main {
          max-width: 960px;
          margin: 36px auto 42px;
          padding: 30px 34px;
          border: 1px solid var(--border);
          border-radius: 18px;
          background: var(--card);
          box-shadow: var(--shadow);
        }
        h1, h2, h3, h4 {
          margin: 0 0 0.5em;
          font-family: "Avenir Next Demi Bold", "Gill Sans", sans-serif;
          letter-spacing: 0.01em;
        }
        p { color: var(--muted); line-height: 1.65; font-size: 1.05rem; }
        kbd {
          padding: 2px 8px;
          border-radius: 7px;
          border: 1px solid var(--border);
          font-family: "Menlo", "SFMono-Regular", monospace;
          font-size: 0.88rem;
          background: var(--code-bg);
        }
        .hint { margin-top: 14px; }
      </style>
    </head>
    <body>
      <main>
        <h1>MDbeaty</h1>
        <p>Fast macOS Markdown viewer with clean typography and embedded image support.</p>
        <p class="hint">Open a file with <kbd>⌘O</kbd> or drop a <kbd>.md</kbd> file into the window.</p>
      </main>
    </body>
    </html>
    """

    static func render(markdown: String, baseFolderURL: URL?, initialFragment: String?) -> String {
        let extracted = extractYAMLFrontMatterIfPresent(markdown)
        let contentMarkdown = extracted.bodyMarkdown
        let parser = MarkdownParser()
        let headingCandidates = extractHeadingCandidates(from: contentMarkdown)
        let normalizedMarkdown = normalizeForInk(contentMarkdown)
        let parsedBodyHTML = parser.html(from: normalizedMarkdown)
        let enhanced = enhanceBodyHTML(parsedBodyHTML, headingCandidates: headingCandidates)

        let baseHref = escapeHTML(baseFolderURL?.absoluteString ?? "")
        let tocHTML = buildTOCHTML(enhanced.tocEntries)
        let layoutClass = enhanced.tocEntries.isEmpty ? "layout no-toc" : "layout has-toc"
        let initialFragmentJS = escapeForJavaScript(initialFragment ?? "")
        let frontMatterHTML = buildFrontMatterHTML(extracted.frontMatter)

        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width,initial-scale=1">
          <base href="\(baseHref)">
          <style>
            :root {
              color-scheme: light dark;
              --bg: #f5f7fa;
              --card: #ffffff;
              --fg: #1f2732;
              --muted: #44505d;
              --accent: #0f6fd6;
              --border: rgba(33, 43, 54, 0.14);
              --quote: #2f6db0;
              --code-bg: #eff3f8;
              --code-fg: #1b2330;
              --shadow: 0 20px 55px rgba(10, 18, 28, 0.08);
              --toc-bg: rgba(255, 255, 255, 0.74);
              --toc-active-bg: rgba(20, 108, 200, 0.12);
              --toc-active-fg: #0f5fba;
              --fm-bg: rgba(15, 111, 214, 0.05);
              --fm-border: rgba(15, 111, 214, 0.35);
              --fm-summary-bg: rgba(15, 111, 214, 0.08);
              --yaml-key: #0b67c0;
              --yaml-string: #9d5f1f;
              --yaml-number: #1f70a8;
              --yaml-bool: #7b3fb4;
              --yaml-null: #cc5500;
              --yaml-punct: #607086;
              --yaml-comment: #7d8795;
            }
            @media (prefers-color-scheme: dark) {
              :root {
                --bg: #0f141b;
                --card: #131b24;
                --fg: #dde5ef;
                --muted: #afbdce;
                --accent: #66b3ff;
                --border: rgba(214, 225, 238, 0.2);
                --quote: #8ec5ff;
                --code-bg: #1a2430;
                --code-fg: #dde7f3;
                --shadow: 0 26px 68px rgba(0, 0, 0, 0.35);
                --toc-bg: rgba(18, 25, 34, 0.78);
                --toc-active-bg: rgba(102, 179, 255, 0.2);
                --toc-active-fg: #90c9ff;
                --fm-bg: rgba(102, 179, 255, 0.1);
                --fm-border: rgba(102, 179, 255, 0.38);
                --fm-summary-bg: rgba(102, 179, 255, 0.13);
                --yaml-key: #79c0ff;
                --yaml-string: #f2a97f;
                --yaml-number: #a5d6ff;
                --yaml-bool: #d2a8ff;
                --yaml-null: #ffb86b;
                --yaml-punct: #93a3b6;
                --yaml-comment: #7d8590;
              }
            }
            html, body {
              margin: 0;
              min-height: 100%;
              background:
                radial-gradient(circle at 14% 14%, rgba(96, 153, 224, 0.16), transparent 44%),
                radial-gradient(circle at 86% 12%, rgba(35, 140, 191, 0.11), transparent 38%),
                var(--bg);
              color: var(--fg);
              font-family: "Avenir Next", "Charter", "Iowan Old Style", serif;
            }
            .layout {
              width: calc(100% - 44px);
              margin: 28px 22px 40px;
              box-sizing: border-box;
              display: grid;
              grid-template-columns: minmax(220px, 290px) minmax(0, 1fr);
              gap: 22px;
              align-items: start;
            }
            .layout.no-toc {
              grid-template-columns: minmax(0, 1fr);
            }
            .toc-panel {
              position: sticky;
              top: 14px;
              max-height: calc(100vh - 28px);
              overflow: auto;
              border: 1px solid var(--border);
              border-radius: 16px;
              background: var(--toc-bg);
              backdrop-filter: blur(8px);
              box-shadow: var(--shadow);
              padding: 12px;
            }
            .toc-title {
              margin: 2px 8px 8px;
              font-family: "Avenir Next Demi Bold", "Gill Sans", sans-serif;
              letter-spacing: 0.02em;
              color: var(--fg);
              font-size: 0.93rem;
              text-transform: uppercase;
            }
            .toc-links {
              display: flex;
              flex-direction: column;
              gap: 2px;
            }
            .toc-link {
              display: block;
              color: var(--muted);
              text-decoration: none;
              line-height: 1.35;
              border-radius: 9px;
              padding: 6px 8px;
              font-size: 0.93rem;
              border: 1px solid transparent;
            }
            .toc-link:hover {
              color: var(--fg);
              border-color: var(--border);
            }
            .toc-link.active {
              color: var(--toc-active-fg);
              background: var(--toc-active-bg);
              border-color: transparent;
            }
            .toc-link.level-1 { padding-left: 8px; font-weight: 650; }
            .toc-link.level-2 { padding-left: 16px; }
            .toc-link.level-3 { padding-left: 24px; }
            .toc-link.level-4 { padding-left: 32px; }
            .toc-link.level-5 { padding-left: 40px; }
            .toc-link.level-6 { padding-left: 48px; }
            .wrap {
              border: 1px solid var(--border);
              border-radius: 18px;
              background: var(--card);
              box-shadow: var(--shadow);
              padding: 30px 34px;
              min-height: calc(100vh - 86px);
            }
            .frontmatter-details {
              margin: 0 0 1.15rem;
              border: 1px solid var(--fm-border);
              border-left: 4px solid var(--fm-border);
              border-radius: 12px;
              background: var(--fm-bg);
              overflow: hidden;
            }
            .frontmatter-summary {
              cursor: pointer;
              padding: 0.62rem 0.78rem;
              font-family: "Avenir Next Demi Bold", "Gill Sans", sans-serif;
              letter-spacing: 0.01em;
              font-size: 0.95rem;
              color: var(--fg);
              background: var(--fm-summary-bg);
              user-select: none;
            }
            .frontmatter-summary::marker {
              color: var(--muted);
            }
            .frontmatter-summary:hover {
              filter: brightness(0.98);
            }
            .frontmatter-details[open] .frontmatter-summary {
              border-bottom: 1px solid var(--border);
            }
            .frontmatter-pre {
              margin: 0;
              padding: 0.72rem 0.84rem 0.86rem;
              background: transparent;
              overflow: auto;
            }
            .frontmatter-code {
              display: block;
              white-space: pre;
              line-height: 1.48;
              font-size: 0.915rem;
              color: var(--fg);
            }
            .yaml-key { color: var(--yaml-key); }
            .yaml-string { color: var(--yaml-string); }
            .yaml-number { color: var(--yaml-number); }
            .yaml-bool { color: var(--yaml-bool); }
            .yaml-null { color: var(--yaml-null); }
            .yaml-punct { color: var(--yaml-punct); }
            .yaml-comment { color: var(--yaml-comment); }
            h1, h2, h3, h4, h5, h6 {
              margin: 1.1em 0 0.52em;
              line-height: 1.2;
              font-family: "Avenir Next Demi Bold", "Gill Sans", sans-serif;
              letter-spacing: 0.01em;
              color: var(--fg);
              scroll-margin-top: 22px;
            }
            h1 { font-size: 2rem; margin-top: 0.1em; }
            h2 { font-size: 1.55rem; }
            h3 { font-size: 1.3rem; }
            p, li, td, th {
              color: var(--muted);
              line-height: 1.67;
              font-size: 1.04rem;
              overflow-wrap: anywhere;
              word-break: break-word;
            }
            a {
              color: var(--accent);
              text-decoration-thickness: 1.5px;
              text-underline-offset: 3px;
            }
            ul, ol {
              padding-left: 1.3rem;
            }
            li + li {
              margin-top: 0.28rem;
            }
            img {
              display: block;
              max-width: 100%;
              margin: 18px auto;
              border-radius: 12px;
              border: 1px solid var(--border);
              box-shadow: 0 11px 30px rgba(0, 0, 0, 0.12);
              height: auto;
            }
            pre, code {
              font-family: "SF Mono", "Menlo", "SFMono-Regular", monospace;
            }
            code {
              padding: 0.18em 0.35em;
              border-radius: 6px;
              background: var(--code-bg);
              color: var(--code-fg);
              font-size: 0.92em;
              max-width: 100%;
            }
            p code, li code, td code, th code, blockquote code {
              white-space: break-spaces;
              overflow-wrap: anywhere;
              word-break: break-word;
            }
            pre {
              overflow-x: auto;
              border-radius: 10px;
              border: 1px solid var(--border);
              background: var(--code-bg);
              padding: 13px 14px;
            }
            pre code {
              padding: 0;
              background: transparent;
              border-radius: 0;
              white-space: pre;
              overflow-wrap: normal;
              word-break: normal;
            }
            blockquote {
              margin: 1rem 0;
              padding: 0.15rem 0 0.15rem 1rem;
              border-left: 3px solid var(--quote);
              color: var(--muted);
            }
            table {
              width: 100%;
              max-width: 100%;
              border-collapse: collapse;
              margin: 14px 0;
            }
            th, td {
              border: 1px solid var(--border);
              padding: 0.45rem 0.6rem;
              text-align: left;
              vertical-align: top;
              overflow-wrap: anywhere;
              word-break: break-word;
            }
            th code, td code {
              overflow-wrap: anywhere;
              word-break: break-word;
            }
            hr {
              border: none;
              border-top: 1px solid var(--border);
              margin: 1.5rem 0;
            }
            @media (max-width: 980px) {
              .layout {
                grid-template-columns: 1fr;
                gap: 14px;
                width: calc(100% - 24px);
                margin: 20px 12px 30px;
              }
              .toc-panel {
                position: static;
                max-height: none;
              }
              .wrap {
                min-height: auto;
                padding: 24px 20px;
              }
            }
          </style>
        </head>
        <body>
          <div class="\(layoutClass)">
            \(tocHTML)
            <main class="wrap markdown-body">
              \(frontMatterHTML)
              \(enhanced.bodyHTML)
            </main>
          </div>
          <script>
            (() => {
              const initialFragment = "\(initialFragmentJS)";
              const tocLinks = Array.from(document.querySelectorAll(".toc-link"));

              const normalizeFragment = (value) => {
                if (!value) return "";
                const raw = value.startsWith("#") ? value.slice(1) : value;
                try {
                  return decodeURIComponent(raw);
                } catch {
                  return raw;
                }
              };

              const sectionByID = new Map();
              for (const link of tocLinks) {
                const fragment = normalizeFragment(link.getAttribute("href") || "");
                if (!fragment) continue;
                const target = document.getElementById(fragment);
                if (target) {
                  sectionByID.set(fragment, { link, target });
                }
              }

              const sections = Array.from(sectionByID.entries())
                .map(([id, data]) => ({ id, link: data.link, target: data.target }));

              const setActive = (id) => {
                if (!tocLinks.length || !id) return;
                for (const link of tocLinks) {
                  const linkFragment = normalizeFragment(link.getAttribute("href") || "");
                  link.classList.toggle("active", linkFragment === id);
                }
              };

              const scrollToFragment = (fragment) => {
                const id = normalizeFragment(fragment);
                if (!id) return false;
                const target = document.getElementById(id);
                if (!target) return false;
                target.scrollIntoView({ block: "start", inline: "nearest" });
                setActive(id);
                return true;
              };

              const updateActiveByScroll = () => {
                if (!sections.length) return;
                const threshold = Math.max(72, Math.round(window.innerHeight * 0.12));
                let current = sections[0];

                for (const section of sections) {
                  if (section.target.getBoundingClientRect().top - threshold <= 0) {
                    current = section;
                  } else {
                    break;
                  }
                }

                setActive(current.id);
              };

              let ticking = false;
              window.addEventListener("scroll", () => {
                if (ticking) return;
                ticking = true;
                requestAnimationFrame(() => {
                  updateActiveByScroll();
                  ticking = false;
                });
              }, { passive: true });

              for (const link of tocLinks) {
                link.addEventListener("click", (event) => {
                  const href = link.getAttribute("href") || "";
                  if (!href.startsWith("#")) return;
                  event.preventDefault();
                  if (scrollToFragment(href)) {
                    history.replaceState(null, "", href);
                  }
                });
              }

              window.addEventListener("hashchange", () => {
                if (!scrollToFragment(window.location.hash)) {
                  updateActiveByScroll();
                }
              });

              const initializeView = () => {
                if (!scrollToFragment(initialFragment) && !scrollToFragment(window.location.hash)) {
                  updateActiveByScroll();
                }
              };

              requestAnimationFrame(initializeView);
              window.addEventListener("load", () => {
                if (window.location.hash) {
                  scrollToFragment(window.location.hash);
                }
                updateActiveByScroll();
              }, { once: true });
            })();
          </script>
        </body>
        </html>
        """
    }

    static func errorHTML(message: String) -> String {
        let escaped = escapeHTML(message)
        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width,initial-scale=1">
          <style>
            :root {
              color-scheme: light dark;
              --bg: #f6f7fb;
              --fg: #1f2732;
              --muted: #5b6572;
            }
            @media (prefers-color-scheme: dark) {
              :root {
                --bg: #0f141b;
                --fg: #dde5ef;
                --muted: #9aa8ba;
              }
            }
            html, body { height: 100%; margin: 0; }
            body {
              display: grid;
              place-items: center;
              background: var(--bg);
              color: var(--fg);
              font-family: "Avenir Next", "Charter", serif;
            }
            p { color: var(--muted); max-width: 720px; text-align: center; }
          </style>
        </head>
        <body>
          <main>
            <h1>Unable to open Markdown file</h1>
            <p>\(escaped)</p>
          </main>
        </body>
        </html>
        """
    }

    private static func buildTOCHTML(_ entries: [TOCEntry]) -> String {
        guard !entries.isEmpty else { return "" }

        var result = "<aside class=\"toc-panel\"><div class=\"toc-title\">On This Page</div><nav class=\"toc-links\">"
        for entry in entries {
            let clampedLevel = min(max(entry.level, 1), 6)
            let href = escapeHTMLAttribute("#" + encodeFragment(entry.id))
            let title = escapeHTML(entry.title)
            result += "<a class=\"toc-link level-\(clampedLevel)\" href=\"\(href)\">\(title)</a>"
        }
        result += "</nav></aside>"
        return result
    }

    private static func enhanceBodyHTML(
        _ bodyHTML: String,
        headingCandidates: [HeadingCandidate]
    ) -> (bodyHTML: String, tocEntries: [TOCEntry]) {
        let pattern = #"<h([1-6])([^>]*)>(.*?)</h\1>"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        ) else {
            return (bodyHTML, [])
        }

        let searchRange = NSRange(bodyHTML.startIndex..<bodyHTML.endIndex, in: bodyHTML)
        let matches = regex.matches(in: bodyHTML, options: [], range: searchRange)
        guard !matches.isEmpty else {
            return (bodyHTML, [])
        }

        var output = ""
        output.reserveCapacity(bodyHTML.count + matches.count * 32)

        var tocEntries: [TOCEntry] = []
        tocEntries.reserveCapacity(matches.count)

        var usedIDs: [String: Int] = [:]
        var currentIndex = bodyHTML.startIndex

        for (index, match) in matches.enumerated() {
            guard
                let fullRange = Range(match.range, in: bodyHTML),
                let levelRange = Range(match.range(at: 1), in: bodyHTML),
                let attributesRange = Range(match.range(at: 2), in: bodyHTML),
                let innerRange = Range(match.range(at: 3), in: bodyHTML)
            else {
                continue
            }

            output += bodyHTML[currentIndex..<fullRange.lowerBound]

            let level = Int(bodyHTML[levelRange]) ?? 1
            let rawAttributes = String(bodyHTML[attributesRange])
            let innerHTML = String(bodyHTML[innerRange])

            let candidate = index < headingCandidates.count ? headingCandidates[index] : nil
            let existingID = extractIDAttribute(from: rawAttributes)
            let headingTitle = normalizedHeadingTitle(from: innerHTML)

            let preferredID: String
            if let existingID, !existingID.isEmpty {
                preferredID = existingID
            } else if let explicitID = candidate?.explicitID, !explicitID.isEmpty {
                preferredID = explicitID
            } else {
                preferredID = slugify(headingTitle)
            }

            let uniqueID = uniqueFragmentID(preferredID, usedIDs: &usedIDs)
            let attributesWithoutID = removeIDAttribute(from: rawAttributes)
            let trimmedAttributes = attributesWithoutID.trimmingCharacters(in: .whitespacesAndNewlines)

            let composedAttributes: String
            if trimmedAttributes.isEmpty {
                composedAttributes = " id=\"\(escapeHTMLAttribute(uniqueID))\""
            } else {
                composedAttributes = " \(trimmedAttributes) id=\"\(escapeHTMLAttribute(uniqueID))\""
            }

            output += "<h\(level)\(composedAttributes)>\(innerHTML)</h\(level)>"

            let title = headingTitle.isEmpty ? "Section \(index + 1)" : headingTitle
            tocEntries.append(TOCEntry(level: level, id: uniqueID, title: title))

            currentIndex = fullRange.upperBound
        }

        output += bodyHTML[currentIndex...]
        return (output, tocEntries)
    }

    private static func extractHeadingCandidates(from markdown: String) -> [HeadingCandidate] {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        var candidates: [HeadingCandidate] = []
        candidates.reserveCapacity(lines.count / 4)

        for rawLine in lines {
            let line = String(rawLine)
            guard let heading = parseATXHeading(line) else { continue }
            candidates.append(HeadingCandidate(level: heading.level, explicitID: heading.explicitID))
        }

        return candidates
    }

    private static func extractYAMLFrontMatterIfPresent(_ markdown: String) -> FrontMatterExtraction {
        var input = markdown
        if input.hasPrefix("\u{FEFF}") {
            input.removeFirst()
        }

        let normalized = input.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---\n") else {
            return FrontMatterExtraction(frontMatter: nil, bodyMarkdown: input)
        }

        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count >= 3 else {
            return FrontMatterExtraction(frontMatter: nil, bodyMarkdown: input)
        }
        guard lines.first == "---" else {
            return FrontMatterExtraction(frontMatter: nil, bodyMarkdown: input)
        }

        var closingIndex: Int?
        for index in 1..<lines.count {
            if lines[index] == "---" || lines[index] == "..." {
                closingIndex = index
                break
            }
        }

        guard let endIndex = closingIndex, endIndex > 1 else {
            return FrontMatterExtraction(frontMatter: nil, bodyMarkdown: input)
        }

        let metadataLines = lines[1..<endIndex]
        let hasYAMLShape = metadataLines.contains { line in
            line.range(of: #"^\s*[\w-]+\s*:"#, options: .regularExpression) != nil
        }
        guard hasYAMLShape else {
            return FrontMatterExtraction(frontMatter: nil, bodyMarkdown: input)
        }

        let frontMatter = Array(lines[0...endIndex]).joined(separator: "\n")
        let remaining = lines.dropFirst(endIndex + 1)
        var body = remaining.joined(separator: "\n")
        while body.hasPrefix("\n") {
            body.removeFirst()
        }
        return FrontMatterExtraction(frontMatter: frontMatter, bodyMarkdown: body)
    }

    private static func buildFrontMatterHTML(_ frontMatter: String?) -> String {
        guard let frontMatter, !frontMatter.isEmpty else { return "" }
        let highlighted = highlightYAMLFrontMatter(frontMatter)
        return """
        <details class="frontmatter-details">
          <summary class="frontmatter-summary">YAML front matter</summary>
          <pre class="frontmatter-pre"><code class="frontmatter-code">\(highlighted)</code></pre>
        </details>
        """
    }

    private static func highlightYAMLFrontMatter(_ frontMatter: String) -> String {
        let lines = frontMatter.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return lines.map(highlightYAMLLine).joined(separator: "\n")
    }

    private static func highlightYAMLLine(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "" }
        if trimmed == "---" || trimmed == "..." {
            return "<span class=\"yaml-punct\">\(escapeHTML(line))</span>"
        }
        if trimmed.hasPrefix("#") {
            return "<span class=\"yaml-comment\">\(escapeHTML(line))</span>"
        }

        let leading = leadingWhitespace(in: line)
        let content = String(line.dropFirst(leading.count))
        let contentRange = NSRange(content.startIndex..<content.endIndex, in: content)

        if let keyRegex = try? NSRegularExpression(pattern: #"^(-\s+)?([A-Za-z0-9_.-]+)(\s*:\s*)(.*)$"#),
           let match = keyRegex.firstMatch(in: content, options: [], range: contentRange) {
            func group(_ index: Int) -> String {
                guard let range = Range(match.range(at: index), in: content) else { return "" }
                return String(content[range])
            }

            let dashPart = group(1)
            let key = group(2)
            let separator = group(3)
            let value = group(4)

            var rendered = escapeHTML(leading)

            if !dashPart.isEmpty {
                let dashSuffix = String(dashPart.dropFirst())
                rendered += "<span class=\"yaml-punct\">-</span>\(escapeHTML(dashSuffix))"
            }

            if let colonIndex = separator.firstIndex(of: ":") {
                let before = String(separator[..<colonIndex])
                let after = String(separator[separator.index(after: colonIndex)...])
                rendered += "<span class=\"yaml-key\">\(escapeHTML(key))</span>"
                rendered += escapeHTML(before)
                rendered += "<span class=\"yaml-punct\">:</span>"
                rendered += escapeHTML(after)
            } else {
                rendered += "<span class=\"yaml-key\">\(escapeHTML(key))</span><span class=\"yaml-punct\">:</span>"
            }

            rendered += highlightYAMLScalarWithComment(value)
            return rendered
        }

        if content.hasPrefix("- ") || content == "-" {
            let suffix = content.count > 1 ? String(content.dropFirst()) : ""
            return escapeHTML(leading) + "<span class=\"yaml-punct\">-</span>" + highlightYAMLScalarWithComment(suffix)
        }

        return escapeHTML(leading) + highlightYAMLScalarWithComment(content)
    }

    private static func highlightYAMLScalarWithComment(_ value: String) -> String {
        let leading = leadingWhitespace(in: value)
        let core = String(value.dropFirst(leading.count))
        guard !core.isEmpty else { return escapeHTML(value) }

        let (valuePart, commentPart) = splitTrailingComment(from: core)
        let valueLeading = leadingWhitespace(in: valuePart)
        let valueTrailing = trailingWhitespace(in: valuePart)
        let token = valuePart
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var rendered = escapeHTML(leading)
        rendered += escapeHTML(valueLeading)
        if !token.isEmpty {
            rendered += highlightYAMLScalarToken(token)
        }
        rendered += escapeHTML(valueTrailing)

        if !commentPart.isEmpty {
            rendered += "<span class=\"yaml-comment\">\(escapeHTML(commentPart))</span>"
        }

        return rendered
    }

    private static func highlightYAMLScalarToken(_ token: String) -> String {
        let lowered = token.lowercased()

        if token.hasPrefix("[") && token.hasSuffix("]") {
            return highlightYAMLInlineSequence(token)
        }
        if token.hasPrefix("'") && token.hasSuffix("'") {
            return "<span class=\"yaml-string\">\(escapeHTML(token))</span>"
        }
        if token.hasPrefix("\"") && token.hasSuffix("\"") {
            return "<span class=\"yaml-string\">\(escapeHTML(token))</span>"
        }
        if token.range(of: #"^-?\d+(\.\d+)?$"#, options: .regularExpression) != nil {
            return "<span class=\"yaml-number\">\(escapeHTML(token))</span>"
        }
        if ["true", "false", "yes", "no", "on", "off"].contains(lowered) {
            return "<span class=\"yaml-bool\">\(escapeHTML(token))</span>"
        }
        if lowered == "null" || token == "~" {
            return "<span class=\"yaml-null\">\(escapeHTML(token))</span>"
        }

        return "<span class=\"yaml-string\">\(escapeHTML(token))</span>"
    }

    private static func highlightYAMLInlineSequence(_ token: String) -> String {
        guard token.count >= 2 else { return escapeHTML(token) }

        let inner = String(token.dropFirst().dropLast())
        if inner.isEmpty {
            return "<span class=\"yaml-punct\">[</span><span class=\"yaml-punct\">]</span>"
        }

        let parts = inner.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        var rendered = "<span class=\"yaml-punct\">[</span>"

        for (index, part) in parts.enumerated() {
            let partLeading = leadingWhitespace(in: part)
            let partTrailing = trailingWhitespace(in: part)
            let partToken = part.trimmingCharacters(in: .whitespacesAndNewlines)

            rendered += escapeHTML(partLeading)
            if !partToken.isEmpty {
                rendered += highlightYAMLScalarToken(partToken)
            }
            rendered += escapeHTML(partTrailing)

            if index < parts.count - 1 {
                rendered += "<span class=\"yaml-punct\">,</span>"
            }
        }

        rendered += "<span class=\"yaml-punct\">]</span>"
        return rendered
    }

    private static func splitTrailingComment(from text: String) -> (String, String) {
        var inSingleQuote = false
        var inDoubleQuote = false
        var escapedInDoubleQuote = false

        for index in text.indices {
            let character = text[index]

            if inDoubleQuote {
                if escapedInDoubleQuote {
                    escapedInDoubleQuote = false
                    continue
                }

                if character == "\\" {
                    escapedInDoubleQuote = true
                    continue
                }
            }

            if character == "'" && !inDoubleQuote {
                inSingleQuote.toggle()
                continue
            }

            if character == "\"" && !inSingleQuote {
                inDoubleQuote.toggle()
                continue
            }

            if character == "#" && !inSingleQuote && !inDoubleQuote {
                if index == text.startIndex {
                    return ("", String(text[index...]))
                }

                let previous = text[text.index(before: index)]
                if previous.isWhitespace {
                    return (String(text[..<index]), String(text[index...]))
                }
            }
        }

        return (text, "")
    }

    private static func leadingWhitespace(in text: String) -> String {
        String(text.prefix { $0 == " " || $0 == "\t" })
    }

    private static func trailingWhitespace(in text: String) -> String {
        let reversed = text.reversed().prefix { $0 == " " || $0 == "\t" }
        return String(reversed.reversed())
    }

    private static func normalizeForInk(_ markdown: String) -> String {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        var normalizedLines: [String] = []
        normalizedLines.reserveCapacity(lines.count + 16)

        for rawLine in lines {
            let line = String(rawLine)

            if let transformedReference = normalizeAngleBracketReference(line) {
                normalizedLines.append(transformedReference)
                continue
            }

            if let heading = parseATXHeading(line), heading.explicitID != nil {
                let cleaned = String(repeating: "#", count: heading.level) + " " + heading.text
                normalizedLines.append(cleaned)
                continue
            }

            normalizedLines.append(line)
        }

        return normalizedLines.joined(separator: "\n")
    }

    private static func parseATXHeading(_ line: String) -> ParsedHeadingLine? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        var index = trimmed.startIndex
        var level = 0
        while index < trimmed.endIndex, trimmed[index] == "#" {
            level += 1
            index = trimmed.index(after: index)
        }

        guard (1...6).contains(level), index < trimmed.endIndex, trimmed[index] == " " else {
            return nil
        }

        let contentStart = trimmed.index(after: index)
        var content = String(trimmed[contentStart...]).trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return nil }

        var explicitID: String?
        if content.hasSuffix("}"),
           let markerRange = content.range(of: "{#", options: .backwards),
           markerRange.upperBound < content.index(before: content.endIndex) {
            let idEnd = content.index(before: content.endIndex)
            let id = String(content[markerRange.upperBound..<idEnd]).trimmingCharacters(in: .whitespaces)
            let headingBody = String(content[..<markerRange.lowerBound]).trimmingCharacters(in: .whitespaces)

            if !id.isEmpty, !headingBody.isEmpty {
                explicitID = id
                content = headingBody
            }
        }

        return ParsedHeadingLine(level: level, text: content, explicitID: explicitID)
    }

    private static func normalizeAngleBracketReference(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["),
              let declarationRange = trimmed.range(of: "]:") else {
            return nil
        }

        let namePart = trimmed[..<declarationRange.upperBound]
        let afterDeclaration = trimmed[declarationRange.upperBound...]
            .trimmingCharacters(in: .whitespaces)

        guard afterDeclaration.first == "<",
              let closingBracket = afterDeclaration.firstIndex(of: ">"),
              closingBracket > afterDeclaration.startIndex else {
            return nil
        }

        let urlStart = afterDeclaration.index(after: afterDeclaration.startIndex)
        let url = afterDeclaration[urlStart..<closingBracket]
        let tailStart = afterDeclaration.index(after: closingBracket)
        let tail = afterDeclaration[tailStart...].trimmingCharacters(in: .whitespaces)

        if tail.isEmpty {
            return "\(namePart) \(url)"
        }

        return "\(namePart) \(url) \(tail)"
    }

    private static func normalizedHeadingTitle(from innerHTML: String) -> String {
        let withoutTags = innerHTML.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        let decoded = decodeHTMLEntities(withoutTags)
        let collapsed = decoded.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        var decoded = text
        decoded = decoded.replacingOccurrences(of: "&amp;", with: "&")
        decoded = decoded.replacingOccurrences(of: "&lt;", with: "<")
        decoded = decoded.replacingOccurrences(of: "&gt;", with: ">")
        decoded = decoded.replacingOccurrences(of: "&quot;", with: "\"")
        decoded = decoded.replacingOccurrences(of: "&#39;", with: "'")
        decoded = decoded.replacingOccurrences(of: "&nbsp;", with: " ")
        return decoded
    }

    private static func extractIDAttribute(from attributes: String) -> String? {
        if let idRange = attributes.range(of: #"id\s*=\s*"([^"]+)""#, options: .regularExpression) {
            let value = attributes[idRange].replacingOccurrences(
                of: #"id\s*=\s*"|"$"#,
                with: "",
                options: .regularExpression
            )
            return value
        }

        if let idRange = attributes.range(of: #"id\s*=\s*'([^']+)'"#, options: .regularExpression) {
            let value = attributes[idRange].replacingOccurrences(
                of: #"id\s*=\s*'|'$"#,
                with: "",
                options: .regularExpression
            )
            return value
        }

        return nil
    }

    private static func removeIDAttribute(from attributes: String) -> String {
        let pattern = #"\s+id\s*=\s*(".*?"|'.*?')"#
        return attributes.replacingOccurrences(
            of: pattern,
            with: "",
            options: .regularExpression
        )
    }

    private static func uniqueFragmentID(_ preferredID: String, usedIDs: inout [String: Int]) -> String {
        let base = preferredID.isEmpty ? "section" : preferredID
        let baseKey = base.lowercased()

        guard let count = usedIDs[baseKey] else {
            usedIDs[baseKey] = 1
            return base
        }

        var candidate = base
        var suffix = count
        repeat {
            suffix += 1
            candidate = "\(base)-\(suffix)"
        } while usedIDs[candidate.lowercased()] != nil

        usedIDs[baseKey] = suffix
        usedIDs[candidate.lowercased()] = 1
        return candidate
    }

    private static func slugify(_ text: String) -> String {
        if text.isEmpty { return "section" }

        let lowercased = text.lowercased()
        let allowed = CharacterSet.alphanumerics
        var slug = ""
        var previousWasDash = false

        for scalar in lowercased.unicodeScalars {
            if allowed.contains(scalar) {
                slug.unicodeScalars.append(scalar)
                previousWasDash = false
            } else if CharacterSet.whitespacesAndNewlines.contains(scalar) || scalar == "-" || scalar == "_" {
                if !previousWasDash {
                    slug.append("-")
                    previousWasDash = true
                }
            }
        }

        let trimmed = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "section" : trimmed
    }

    private static func encodeFragment(_ fragment: String) -> String {
        fragment.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? fragment
    }

    private static func escapeForJavaScript(_ text: String) -> String {
        var escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        escaped = escaped.replacingOccurrences(of: "\n", with: "\\n")
        escaped = escaped.replacingOccurrences(of: "\r", with: "")
        return escaped
    }

    private static func escapeHTML(_ text: String) -> String {
        var escaped = text.replacingOccurrences(of: "&", with: "&amp;")
        escaped = escaped.replacingOccurrences(of: "<", with: "&lt;")
        escaped = escaped.replacingOccurrences(of: ">", with: "&gt;")
        escaped = escaped.replacingOccurrences(of: "\"", with: "&quot;")
        return escaped
    }

    private static func escapeHTMLAttribute(_ text: String) -> String {
        var escaped = escapeHTML(text)
        escaped = escaped.replacingOccurrences(of: "'", with: "&#39;")
        return escaped
    }
}
