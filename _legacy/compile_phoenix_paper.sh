#!/bin/bash

# Compile Phoenix Protocol Research Paper

echo "📄 Compiling Phoenix Protocol LaTeX Paper..."

cd docs

# Check if pdflatex is installed
if ! command -v pdflatex &> /dev/null; then
    echo "❌ pdflatex not installed"
    echo "Install via: brew install --cask mactex (macOS) or apt-get install texlive-full (Linux)"
    exit 1
fi

# Compile LaTeX document (run twice for references)
pdflatex phoenix_protocol_paper.tex
pdflatex phoenix_protocol_paper.tex

# Clean up auxiliary files
rm -f phoenix_protocol_paper.aux
rm -f phoenix_protocol_paper.log
rm -f phoenix_protocol_paper.out

echo "✅ Paper compiled successfully!"
echo "📖 Output: docs/phoenix_protocol_paper.pdf"

# Open PDF if on macOS
if [[ "$OSTYPE" == "darwin"* ]]; then
    open phoenix_protocol_paper.pdf
fi
