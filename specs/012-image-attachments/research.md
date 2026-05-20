# Research: Image Attachments

**Feature**: 012-image-attachments
**Date**: 2026-05-19

## Decision 1: Image Encoding Format for LLM APIs

**Decision**: Use base64 encoding for all providers. Each provider gets its own content block format.

**Rationale**: All four supported providers (OpenAI, Anthropic, Gemini, Ollama) accept base64-encoded images. URL-based approaches require hosting infrastructure. Base64 is self-contained, works offline (important for Ollama), and requires no external dependencies.

**Provider-specific formats**:

| Provider | Format | Content Structure |
|----------|--------|-------------------|
| OpenAI | Data URI in `image_url` | `{"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,{data}", "detail": "auto"}}` |
| Anthropic | Explicit base64 source | `{"type": "image", "source": {"type": "base64", "media_type": "image/jpeg", "data": "{data}"}}` |
| Gemini | Inline data part | `{"inlineData": {"mimeType": "image/jpeg", "data": "{data}"}}` |
| Ollama | Separate images array | Message gets `"images": ["{raw_base64}"]` field (no data URI prefix) |

**Alternatives considered**:
- URL-based hosting: Requires server infrastructure, doesn't work offline. Rejected.
- File upload APIs (OpenAI Files, Anthropic Files): Adds complexity for marginal benefit in a desktop app. Could be added later.

## Decision 2: Image Resizing Strategy

**Decision**: Resize to max 1568px on the longest edge using ImageIO framework. Compress to JPEG at 0.85 quality. Target <1MB per image after processing.

**Rationale**: 1568px covers all providers comfortably (Anthropic's optimal limit for non-Opus models is 1568px, OpenAI high detail goes up to 2048px but auto-tiles, Gemini tiles at 768px). ImageIO's `CGImageSourceCreateThumbnailAtIndex` is the most memory-efficient approach on macOS — a 20MB image only requires ~24MB RAM when downsampled via ImageIO vs ~220MB when fully decoded first.

**Alternatives considered**:
- Core Graphics (`CGContext.draw`): Slightly faster but higher memory usage for large images. Rejected for memory efficiency.
- vImage/Core Image: Much slower (2.3-2.5s vs 0.16s). Rejected.
- No resizing (send original): Risk of exceeding API limits (Anthropic 5MB/image) and wasting tokens. Rejected.

## Decision 3: Image Persistence Strategy

**Decision**: Hybrid approach — store full-resolution processed images as files in `~/Library/Application Support/Extremis/images/{uuid}.jpg`. Store thumbnail as inline base64 in the persisted message JSON for fast preview rendering.

**Rationale**: File-based storage keeps JSON session files small and fast to parse. Inline thumbnails (~5-15KB each as base64) enable instant preview on session restore without file I/O. This is the pattern used by production chat apps (Slack, Discord).

**Alternatives considered**:
- Full base64 inline in JSON: Bloats session files (a 10-image conversation adds 3-5MB to JSON), slows parsing. Rejected.
- File references only (no inline thumbnail): Requires file I/O for every thumbnail on session load, slower perceived startup. Rejected.

## Decision 4: Thumbnail Dimensions and Format

**Decision**: Generate thumbnails at 200px on the longest edge, JPEG at 0.6 quality. Typical size: 5-15KB.

**Rationale**: 200px thumbnails are sufficient for the 80-120px display size in the attachment strip (provides 1.5-2.5x for Retina). JPEG at 0.6 keeps size under 15KB while remaining visually acceptable for preview purposes.

**Alternatives considered**:
- 100px thumbnails: Too small for Retina displays. Rejected.
- PNG thumbnails: 3-5x larger file size for no visual benefit at thumbnail size. Rejected.

## Decision 5: Vision Capability Detection

**Decision**: Add `"supportsVision": true/false` to the `capabilities` object in `models.json`, consistent with existing `supportsTools` pattern. For Ollama, use a heuristic based on known vision model families.

**Rationale**: Static metadata in `models.json` is simple, reliable, and follows the established pattern. Ollama doesn't expose vision capability via API, so a heuristic (model names containing "llava", "vision", "gemma3", etc.) is the practical approach.

**Known vision models by provider**:
- OpenAI: gpt-4o, gpt-4o-mini, gpt-4-turbo (all current models)
- Anthropic: claude-3-opus, claude-3-sonnet, claude-3-haiku, claude-3.5-sonnet, claude-3.5-haiku, claude-4-opus, claude-4-sonnet (all Claude 3+ models)
- Gemini: gemini-1.5-pro, gemini-1.5-flash, gemini-2.0-flash (all current models)
- Ollama: llava, llama3.2-vision, gemma3, qwen3-vl (varies by model)

**Alternatives considered**:
- Runtime API query (`/v1/models` endpoint): Only OpenAI exposes this reliably. Adds network dependency. Rejected for initial implementation.
- User toggle per model: More flexible but adds UX burden. Could be added later for Ollama custom models.

## Decision 6: Supported Image Formats

**Decision**: Accept PNG, JPEG, GIF (non-animated), WebP, HEIC/HEIF at input. Convert HEIC to JPEG before sending. Send as JPEG for photos/screenshots, PNG for images with transparency.

**Rationale**: macOS ImageIO natively reads all these formats. HEIC is common on macOS (screenshots, Photos.app exports). All providers accept JPEG and PNG. Gemini is the only provider that natively accepts HEIC, but converting to JPEG ensures universal compatibility.

**Alternatives considered**:
- HEIC passthrough to Gemini: Would complicate the pipeline for marginal benefit. Rejected.
- Support animated GIF: Adds complexity (multi-frame handling) for a niche use case. Rejected for initial scope.

## Decision 7: API Size Limits per Provider

**Decision**: Apply a universal 4MB-per-image limit after processing (well within all providers' limits). Display error if an image exceeds 10MB before processing and cannot be compressed below 4MB.

| Provider | Image Size Limit | Request Size Limit |
|----------|-----------------|-------------------|
| OpenAI | 512MB (generous) | 512MB |
| Anthropic | 5MB per image | 32MB request |
| Gemini | 20MB inline | 20MB request |
| Ollama | Undocumented | Internal resize |

**Rationale**: Anthropic's 5MB limit is the most restrictive. A 4MB universal limit provides safety margin. With resizing to 1568px and JPEG 0.85, virtually all images will be well under 1MB.

## Decision 8: Clipboard Handling Behavior

**Decision**: On Cmd+V, check NSPasteboard for image types first (TIFF, PNG, JPEG). If an image is found, attach it. If only text is found, paste text as normal. If both are present, attach the image AND paste the text.

**Rationale**: NSPasteboard can contain multiple types simultaneously (e.g., a webpage copy may have both HTML text and a rendered image). Handling both ensures no data loss. This matches the behavior specified in the spec's edge cases.

**macOS clipboard image types to check** (in priority order):
1. `public.tiff` (NSPasteboard's native image format)
2. `public.png`
3. `public.jpeg`
4. `public.heic`

## Decision 9: Maximum Images per Message

**Decision**: Default maximum of 5 images per message. Configurable constant but not user-facing preference initially.

**Rationale**: 5 images covers common comparison scenarios (2-3 images) with headroom. Anthropic's limit is 20 on claude.ai and 100+ via API. OpenAI supports up to 1,500. 5 is a conservative, sensible default that prevents token budget issues.

**Alternatives considered**:
- 10 images: More generous but increases token cost significantly. Could be raised later.
- Provider-specific limits: Adds complexity. Rejected for initial scope.
