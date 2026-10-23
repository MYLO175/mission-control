#!/usr/bin/env python3
"""Regenerate the public Markdown catalogue and offline visual chooser."""
import html, json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def main():
    catalogue=json.loads((ROOT/'catalog.json').read_text())
    features=catalogue['features']
    text='''# Choose what belongs in your space

Start with a simple foundation, then add what helps. Your coding assistant will explain the options and implement only your choices. You can add more later.

## The common starting point

![The real foundation rendered with fictional chat and daily brief](assets/foundation.png)

**Conversation:** an ongoing chat with local history and your own connected ChatGPT account. **Daily brief:** a short overview generated when you ask, using priorities you enter and recent conversation. Calendar, Reminders and automatic background work are not required. The supplied appearance is applied automatically; you can change it.

This image is a render of the actual foundation with fictional information. The optional feature images below are **illustrations**, not screenshots of a live customer's data or proof of ready-made modules.

Open [the visual chooser](chooser.html) locally for larger previews and a shortlist you can copy to your coding assistant.

## Optional features

'''
    for f in features:
        text+=f"### {f['title']}\n\n{f['summary']}\n\n![Illustrative {f['title']} preview](assets/features/{f['id']}.png)\n\n{f['why']}\n\n**{f['status']}** · Relative implementation size: {f['effort']}.\n\n[Explore this feature](../{f['recipe']})\n\n"
    text+='''## A first version can be very small

Choose chat and a brief, or add one useful connection. You do not need every feature. Review is separate from heartbeat; Projects is separate from Apple Reminders; contextual memory is separate from chat history. A feature's guide explains dependencies and any new access it requires.

[Start the setup conversation](../START_HERE.md) · [Mac setup](MAC_SETUP.md)
'''
    (ROOT/'docs/FEATURES.md').write_text(text)
    template=(ROOT/'docs/chooser.template.html').read_text()
    output=template.replace('__CATALOGUE_JSON__',json.dumps(catalogue,ensure_ascii=False).replace('</','<\\/'))
    (ROOT/'docs/chooser.html').write_text(output)
    print(f'Generated catalogue and chooser for {len(features)} optional features.')
if __name__=='__main__': main()
