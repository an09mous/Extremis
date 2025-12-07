#!/usr/bin/env python3
"""Generate a DMG background image with drag-to-Applications arrow"""

import subprocess
import os

def create_background(output_path, width=600, height=400):
    """Create a simple DMG background using sips and basic drawing"""
    
    # Create SVG content
    svg_content = f'''<?xml version="1.0" encoding="UTF-8"?>
<svg width="{width}" height="{height}" xmlns="http://www.w3.org/2000/svg">
  <!-- Background gradient -->
  <defs>
    <linearGradient id="bg" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" style="stop-color:#2d2d2d"/>
      <stop offset="100%" style="stop-color:#1a1a1a"/>
    </linearGradient>
  </defs>
  <rect width="{width}" height="{height}" fill="url(#bg)"/>
  
  <!-- Arrow pointing from app to Applications -->
  <defs>
    <marker id="arrowhead" markerWidth="10" markerHeight="7" refX="9" refY="3.5" orient="auto">
      <polygon points="0 0, 10 3.5, 0 7" fill="#888888"/>
    </marker>
  </defs>
  
  <!-- Arrow line -->
  <line x1="380" y1="200" x2="220" y2="200" 
        stroke="#888888" stroke-width="3" 
        marker-end="url(#arrowhead)"
        stroke-dasharray="10,5"/>
  
  <!-- Instruction text -->
  <text x="{width//2}" y="340" 
        font-family="SF Pro Display, Helvetica Neue, Arial" 
        font-size="16" 
        fill="#999999" 
        text-anchor="middle">
    Drag Extremis to Applications to install
  </text>
</svg>'''
    
    svg_path = output_path.replace('.png', '.svg')
    
    # Write SVG
    with open(svg_path, 'w') as f:
        f.write(svg_content)
    
    # Convert SVG to PNG using built-in tools
    # First try using qlmanage (Quick Look)
    try:
        subprocess.run([
            'qlmanage', '-t', '-s', str(max(width, height)), '-o', 
            os.path.dirname(output_path) or '.', svg_path
        ], capture_output=True, check=True)
        
        # qlmanage adds .png to the filename
        generated = svg_path + '.png'
        if os.path.exists(generated):
            os.rename(generated, output_path)
            os.remove(svg_path)
            return True
    except:
        pass
    
    # Fallback: just keep SVG and let the script handle it
    os.rename(svg_path, output_path.replace('.png', '.svg'))
    print(f"Created SVG background (PNG conversion not available)")
    return False

if __name__ == '__main__':
    import sys
    output = sys.argv[1] if len(sys.argv) > 1 else 'dmg_background.png'
    create_background(output)
    print(f"Created: {output}")

