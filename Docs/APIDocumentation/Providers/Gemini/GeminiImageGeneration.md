<br />

<br />

Gemini can generate and process images conversationally. You can prompt Gemini with text, images, or a combination of both allowing you to create, edit, and iterate on visuals with unprecedented control:

- **Text-to-Image:**Generate high-quality images from simple or complex text descriptions.
- **Image + Text-to-Image (Editing):**Provide an image and use text prompts to add, remove, or modify elements, change the style, or adjust the color grading.
- **Multi-Image to Image (Composition \& Style Transfer):**Use multiple input images to compose a new scene or transfer the style from one image to another.
- **Iterative Refinement:**Engage in a conversation to progressively refine your image over multiple turns, making small adjustments until it's perfect.
- **High-Fidelity Text Rendering:**Accurately generate images that contain legible and well-placed text, ideal for logos, diagrams, and posters.

All generated images include a[SynthID watermark](https://ai.google.dev/responsible/docs/safeguards/synthid).

## Image generation (text-to-image)

The following code demonstrates how to generate an image based on a descriptive prompt.  

### Python

    from google import genai
    from google.genai import types
    from PIL import Image

    client = genai.Client()

    prompt = (
        "Create a picture of a nano banana dish in a fancy restaurant with a Gemini theme"
    )

    response = client.models.generate_content(
        model="gemini-2.5-flash-image",
        contents=[prompt],
    )

    for part in response.parts:
        if part.text is not None:
            print(part.text)
        elif part.inline_data is not None:
            image = part.as_image()
            image.save("generated_image.png")

### JavaScript

    import { GoogleGenAI } from "@google/genai";
    import * as fs from "node:fs";

    async function main() {

      const ai = new GoogleGenAI({});

      const prompt =
        "Create a picture of a nano banana dish in a fancy restaurant with a Gemini theme";

      const response = await ai.models.generateContent({
        model: "gemini-2.5-flash-image",
        contents: prompt,
      });
      for (const part of response.parts) {
        if (part.text) {
          console.log(part.text);
        } else if (part.inlineData) {
          const imageData = part.inlineData.data;
          const buffer = Buffer.from(imageData, "base64");
          fs.writeFileSync("gemini-native-image.png", buffer);
          console.log("Image saved as gemini-native-image.png");
        }
      }
    }

    main();

### Go

    package main

    import (
      "context"
      "fmt"
      "os"
      "google.golang.org/genai"
    )

    func main() {

      ctx := context.Background()
      client, err := genai.NewClient(ctx, nil)
      if err != nil {
          log.Fatal(err)
      }

      result, _ := client.Models.GenerateContent(
          ctx,
          "gemini-2.5-flash-image",
          genai.Text("Create a picture of a nano banana dish in a " +
                     " fancy restaurant with a Gemini theme"),
      )

      for _, part := range result.Candidates[0].Content.Parts {
          if part.Text != "" {
              fmt.Println(part.Text)
          } else if part.InlineData != nil {
              imageBytes := part.InlineData.Data
              outputFilename := "gemini_generated_image.png"
              _ = os.WriteFile(outputFilename, imageBytes, 0644)
          }
      }
    }

### REST

    curl -s -X POST \
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:generateContent" \
      -H "x-goog-api-key: $GEMINI_API_KEY" \
      -H "Content-Type: application/json" \
      -d '{
        "contents": [{
          "parts": [
            {"text": "Create a picture of a nano banana dish in a fancy restaurant with a Gemini theme"}
          ]
        }]
      }' \
      | grep -o '"data": "[^"]*"' \
      | cut -d'"' -f4 \
      | base64 --decode > gemini-native-image.png

![AI-generated image of a nano banana dish](https://ai.google.dev/static/gemini-api/docs/images/nano-banana.png)AI-generated image of a nano banana dish in a Gemini-themed restaurant

## Image editing (text-and-image-to-image)

**Reminder** : Make sure you have the necessary rights to any images you upload. Don't generate content that infringe on others' rights, including videos or images that deceive, harass, or harm. Your use of this generative AI service is subject to our[Prohibited Use Policy](https://policies.google.com/terms/generative-ai/use-policy).

The following example demonstrates uploading base64 encoded images. For multiple images, larger payloads, and supported MIME types, check the[Image understanding](https://ai.google.dev/gemini-api/docs/image-understanding)page.  

### Python

    from google import genai
    from google.genai import types
    from PIL import Image

    client = genai.Client()

    prompt = (
        "Create a picture of my cat eating a nano-banana in a "
        "fancy restaurant under the Gemini constellation",
    )

    image = Image.open("/path/to/cat_image.png")

    response = client.models.generate_content(
        model="gemini-2.5-flash-image",
        contents=[prompt, image],
    )

    for part in response.parts:
        if part.text is not None:
            print(part.text)
        elif part.inline_data is not None:
            image = part.as_image()
            image.save("generated_image.png")

### JavaScript

    import { GoogleGenAI } from "@google/genai";
    import * as fs from "node:fs";

    async function main() {

      const ai = new GoogleGenAI({});

      const imagePath = "path/to/cat_image.png";
      const imageData = fs.readFileSync(imagePath);
      const base64Image = imageData.toString("base64");

      const prompt = [
        { text: "Create a picture of my cat eating a nano-banana in a" +
                "fancy restaurant under the Gemini constellation" },
        {
          inlineData: {
            mimeType: "image/png",
            data: base64Image,
          },
        },
      ];

      const response = await ai.models.generateContent({
        model: "gemini-2.5-flash-image",
        contents: prompt,
      });
      for (const part of response.parts) {
        if (part.text) {
          console.log(part.text);
        } else if (part.inlineData) {
          const imageData = part.inlineData.data;
          const buffer = Buffer.from(imageData, "base64");
          fs.writeFileSync("gemini-native-image.png", buffer);
          console.log("Image saved as gemini-native-image.png");
        }
      }
    }

    main();

### Go

    package main

    import (
     "context"
     "fmt"
     "os"
     "google.golang.org/genai"
    )

    func main() {

     ctx := context.Background()
     client, err := genai.NewClient(ctx, nil)
     if err != nil {
         log.Fatal(err)
     }

     imagePath := "/path/to/cat_image.png"
     imgData, _ := os.ReadFile(imagePath)

     parts := []*genai.Part{
       genai.NewPartFromText("Create a picture of my cat eating a nano-banana in a fancy restaurant under the Gemini constellation"),
       &genai.Part{
         InlineData: &genai.Blob{
           MIMEType: "image/png",
           Data:     imgData,
         },
       },
     }

     contents := []*genai.Content{
       genai.NewContentFromParts(parts, genai.RoleUser),
     }

     result, _ := client.Models.GenerateContent(
         ctx,
         "gemini-2.5-flash-image",
         contents,
     )

     for _, part := range result.Candidates[0].Content.Parts {
         if part.Text != "" {
             fmt.Println(part.Text)
         } else if part.InlineData != nil {
             imageBytes := part.InlineData.Data
             outputFilename := "gemini_generated_image.png"
             _ = os.WriteFile(outputFilename, imageBytes, 0644)
         }
     }
    }

### REST

    IMG_PATH=/path/to/cat_image.jpeg

    if [[ "$(base64 --version 2>&1)" = *"FreeBSD"* ]]; then
      B64FLAGS="--input"
    else
      B64FLAGS="-w0"
    fi

    IMG_BASE64=$(base64 "$B64FLAGS" "$IMG_PATH" 2>&1)

    curl -X POST \
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:generateContent" \
        -H "x-goog-api-key: $GEMINI_API_KEY" \
        -H 'Content-Type: application/json' \
        -d "{
          \"contents\": [{
            \"parts\":[
                {\"text\": \"'Create a picture of my cat eating a nano-banana in a fancy restaurant under the Gemini constellation\"},
                {
                  \"inline_data\": {
                    \"mime_type\":\"image/jpeg\",
                    \"data\": \"$IMG_BASE64\"
                  }
                }
            ]
          }]
        }"  \
      | grep -o '"data": "[^"]*"' \
      | cut -d'"' -f4 \
      | base64 --decode > gemini-edited-image.png

![AI-generated image of a cat eating anano banana](https://ai.google.dev/static/gemini-api/docs/images/cat-banana.png)AI-generated image of a cat eating a nano banana

## Other image generation modes

Gemini supports other image interaction modes based on prompt structure and context, including:

- **Text to image(s) and text (interleaved):** Outputs images with related text.
  - Example prompt: "Generate an illustrated recipe for a paella."
- **Image(s) and text to image(s) and text (interleaved)** : Uses input images and text to create new related images and text.
  - Example prompt: (With an image of a furnished room) "What other color sofas would work in my space? can you update the image?"
- **Multi-turn image editing (chat):** Keep generating and editing images conversationally.
  - Example prompts: \[upload an image of a blue car.\] , "Turn this car into a convertible.", "Now change the color to yellow."

## Prompting guide and strategies

Mastering Gemini 2.5 Flash Image Generation starts with one fundamental principle:
> **Describe the scene, don't just list keywords.**The model's core strength is its deep language understanding. A narrative, descriptive paragraph will almost always produce a better, more coherent image than a list of disconnected words.

### Prompts for generating images

The following strategies will help you create effective prompts to generate exactly the images you're looking for.

#### 1. Photorealistic scenes

For realistic images, use photography terms. Mention camera angles, lens types, lighting, and fine details to guide the model toward a photorealistic result.  

### Template

    A photorealistic [shot type] of [subject], [action or expression], set in
    [environment]. The scene is illuminated by [lighting description], creating
    a [mood] atmosphere. Captured with a [camera/lens details], emphasizing
    [key textures and details]. The image should be in a [aspect ratio] format.

### Prompt

    A photorealistic close-up portrait of an elderly Japanese ceramicist with
    deep, sun-etched wrinkles and a warm, knowing smile. He is carefully
    inspecting a freshly glazed tea bowl. The setting is his rustic,
    sun-drenched workshop. The scene is illuminated by soft, golden hour light
    streaming through a window, highlighting the fine texture of the clay.
    Captured with an 85mm portrait lens, resulting in a soft, blurred background
    (bokeh). The overall mood is serene and masterful. Vertical portrait
    orientation.

### Python

    from google import genai
    from google.genai import types
    from PIL import Image

    client = genai.Client()

    # Generate an image from a text prompt
    response = client.models.generate_content(
        model="gemini-2.5-flash-image",
        contents="A photorealistic close-up portrait of an elderly Japanese ceramicist with deep, sun-etched wrinkles and a warm, knowing smile. He is carefully inspecting a freshly glazed tea bowl. The setting is his rustic, sun-drenched workshop with pottery wheels and shelves of clay pots in the background. The scene is illuminated by soft, golden hour light streaming through a window, highlighting the fine texture of the clay and the fabric of his apron. Captured with an 85mm portrait lens, resulting in a soft, blurred background (bokeh). The overall mood is serene and masterful.",
    )

    image_parts = [
        part.inline_data.data
        for part in response.parts
        if part.inline_data
    ]

    if image_parts:
        image = part.as_image()
        image.save('photorealistic_example.png')
        image.show()

### JavaScript

    import { GoogleGenAI } from "@google/genai";
    import * as fs from "node:fs";

    async function main() {

      const ai = new GoogleGenAI({});

      const prompt =
        "A photorealistic close-up portrait of an elderly Japanese ceramicist with deep, sun-etched wrinkles and a warm, knowing smile. He is carefully inspecting a freshly glazed tea bowl. The setting is his rustic, sun-drenched workshop with pottery wheels and shelves of clay pots in the background. The scene is illuminated by soft, golden hour light streaming through a window, highlighting the fine texture of the clay and the fabric of his apron. Captured with an 85mm portrait lens, resulting in a soft, blurred background (bokeh). The overall mood is serene and masterful.";

      const response = await ai.models.generateContent({
        model: "gemini-2.5-flash-image",
        contents: prompt,
      });
      for (const part of response.parts) {
        if (part.text) {
          console.log(part.text);
        } else if (part.inlineData) {
          const imageData = part.inlineData.data;
          const buffer = Buffer.from(imageData, "base64");
          fs.writeFileSync("photorealistic_example.png", buffer);
          console.log("Image saved as photorealistic_example.png");
        }
      }
    }

    main();

### Go

    package main

    import (
        "context"
        "fmt"
        "os"
        "google.golang.org/genai"
    )

    func main() {

        ctx := context.Background()
        client, err := genai.NewClient(ctx, nil)
        if err != nil {
            log.Fatal(err)
        }

        result, _ := client.Models.GenerateContent(
            ctx,
            "gemini-2.5-flash-image",
            genai.Text("A photorealistic close-up portrait of an elderly Japanese ceramicist with deep, sun-etched wrinkles and a warm, knowing smile. He is carefully inspecting a freshly glazed tea bowl. The setting is his rustic, sun-drenched workshop with pottery wheels and shelves of clay pots in the background. The scene is illuminated by soft, golden hour light streaming through a window, highlighting the fine texture of the clay and the fabric of his apron. Captured with an 85mm portrait lens, resulting in a soft, blurred background (bokeh). The overall mood is serene and masterful."),
        )

        for _, part := range result.Candidates[0].Content.Parts {
            if part.Text != "" {
                fmt.Println(part.Text)
            } else if part.InlineData != nil {
                imageBytes := part.InlineData.Data
                outputFilename := "photorealistic_example.png"
                _ = os.WriteFile(outputFilename, imageBytes, 0644)
            }
        }
    }

### REST

    curl -s -X POST
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:generateContent" \
      -H "x-goog-api-key: $GEMINI_API_KEY" \
      -H "Content-Type: application/json" \
      -d '{
        "contents": [{
          "parts": [
            {"text": "A photorealistic close-up portrait of an elderly Japanese ceramicist with deep, sun-etched wrinkles and a warm, knowing smile. He is carefully inspecting a freshly glazed tea bowl. The setting is his rustic, sun-drenched workshop with pottery wheels and shelves of clay pots in the background. The scene is illuminated by soft, golden hour light streaming through a window, highlighting the fine texture of the clay and the fabric of his apron. Captured with an 85mm portrait lens, resulting in a soft, blurred background (bokeh). The overall mood is serene and masterful."}
          ]
        }]
      }' \
      | grep -o '"data": "[^"]*"' \
      | cut -d'"' -f4 \
      | base64 --decode > photorealistic_example.png

![A photorealistic close-up portrait of an elderly Japanese ceramicist...](https://ai.google.dev/static/gemini-api/docs/images/photorealistic_example.png)A photorealistic close-up portrait of an elderly Japanese ceramicist...

#### 2. Stylized illustrations \& stickers

To create stickers, icons, or assets, be explicit about the style and request a transparent background.  

### Template

    A [style] sticker of a [subject], featuring [key characteristics] and a
    [color palette]. The design should have [line style] and [shading style].
    The background must be transparent.

### Prompt

    A kawaii-style sticker of a happy red panda wearing a tiny bamboo hat. It's
    munching on a green bamboo leaf. The design features bold, clean outlines,
    simple cel-shading, and a vibrant color palette. The background must be white.

### Python

    from google import genai
    from google.genai import types
    from PIL import Image

    client = genai.Client()

    # Generate an image from a text prompt
    response = client.models.generate_content(
        model="gemini-2.5-flash-image",
        contents="A kawaii-style sticker of a happy red panda wearing a tiny bamboo hat. It's munching on a green bamboo leaf. The design features bold, clean outlines, simple cel-shading, and a vibrant color palette. The background must be white.",
    )

    image_parts = [
        part.inline_data.data
        for part in response.parts
        if part.inline_data
    ]

    if image_parts:
        image = part.as_image()
        image.save('red_panda_sticker.png')
        image.show()

### JavaScript

    import { GoogleGenAI } from "@google/genai";
    import * as fs from "node:fs";

    async function main() {

      const ai = new GoogleGenAI({});

      const prompt =
        "A kawaii-style sticker of a happy red panda wearing a tiny bamboo hat. It's munching on a green bamboo leaf. The design features bold, clean outlines, simple cel-shading, and a vibrant color palette. The background must be white.";

      const response = await ai.models.generateContent({
        model: "gemini-2.5-flash-image",
        contents: prompt,
      });
      for (const part of response.parts) {
        if (part.text) {
          console.log(part.text);
        } else if (part.inlineData) {
          const imageData = part.inlineData.data;
          const buffer = Buffer.from(imageData, "base64");
          fs.writeFileSync("red_panda_sticker.png", buffer);
          console.log("Image saved as red_panda_sticker.png");
        }
      }
    }

    main();

### Go

    package main

    import (
        "context"
        "fmt"
        "os"
        "google.golang.org/genai"
    )

    func main() {

        ctx := context.Background()
        client, err := genai.NewClient(ctx, nil)
        if err != nil {
            log.Fatal(err)
        }

        result, _ := client.Models.GenerateContent(
            ctx,
            "gemini-2.5-flash-image",
            genai.Text("A kawaii-style sticker of a happy red panda wearing a tiny bamboo hat. It's munching on a green bamboo leaf. The design features bold, clean outlines, simple cel-shading, and a vibrant color palette. The background must be white."),
        )

        for _, part := range result.Candidates[0].Content.Parts {
            if part.Text != "" {
                fmt.Println(part.Text)
            } else if part.InlineData != nil {
                imageBytes := part.InlineData.Data
                outputFilename := "red_panda_sticker.png"
                _ = os.WriteFile(outputFilename, imageBytes, 0644)
            }
        }
    }

### REST

    curl -s -X POST
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:generateContent" \
      -H "x-goog-api-key: $GEMINI_API_KEY" \
      -H "Content-Type: application/json" \
      -d '{
        "contents": [{
          "parts": [
            {"text": "A kawaii-style sticker of a happy red panda wearing a tiny bamboo hat. It'"'"'s munching on a green bamboo leaf. The design features bold, clean outlines, simple cel-shading, and a vibrant color palette. The background must be white."}
          ]
        }]
      }' \
      | grep -o '"data": "[^"]*"' \
      | cut -d'"' -f4 \
      | base64 --decode > red_panda_sticker.png

![A kawaii-style sticker of a happy red...](https://ai.google.dev/static/gemini-api/docs/images/red_panda_sticker.png)A kawaii-style sticker of a happy red panda...

#### 3. Accurate text in images

Gemini excels at rendering text. Be clear about the text, the font style (descriptively), and the overall design.  

### Template

    Create a [image type] for [brand/concept] with the text "[text to render]"
    in a [font style]. The design should be [style description], with a
    [color scheme].

### Prompt

    Create a modern, minimalist logo for a coffee shop called 'The Daily Grind'.
    The text should be in a clean, bold, sans-serif font. The design should
    feature a simple, stylized icon of a a coffee bean seamlessly integrated
    with the text. The color scheme is black and white.

### Python

    from google import genai
    from google.genai import types
    from PIL import Image

    client = genai.Client()

    # Generate an image from a text prompt
    response = client.models.generate_content(
        model="gemini-2.5-flash-image",
        contents="Create a modern, minimalist logo for a coffee shop called 'The Daily Grind'. The text should be in a clean, bold, sans-serif font. The design should feature a simple, stylized icon of a a coffee bean seamlessly integrated with the text. The color scheme is black and white.",
    )

    image_parts = [
        part.inline_data.data
        for part in response.parts
        if part.inline_data
    ]

    if image_parts:
        image = part.as_image()
        image.save('logo_example.png')
        image.show()

### JavaScript

    import { GoogleGenAI } from "@google/genai";
    import * as fs from "node:fs";

    async function main() {

      const ai = new GoogleGenAI({});

      const prompt =
        "Create a modern, minimalist logo for a coffee shop called 'The Daily Grind'. The text should be in a clean, bold, sans-serif font. The design should feature a simple, stylized icon of a a coffee bean seamlessly integrated with the text. The color scheme is black and white.";

      const response = await ai.models.generateContent({
        model: "gemini-2.5-flash-image",
        contents: prompt,
      });
      for (const part of response.parts) {
        if (part.text) {
          console.log(part.text);
        } else if (part.inlineData) {
          const imageData = part.inlineData.data;
          const buffer = Buffer.from(imageData, "base64");
          fs.writeFileSync("logo_example.png", buffer);
          console.log("Image saved as logo_example.png");
        }
      }
    }

    main();

### Go

    package main

    import (
        "context"
        "fmt"
        "os"
        "google.golang.org/genai"
    )

    func main() {

        ctx := context.Background()
        client, err := genai.NewClient(ctx, nil)
        if err != nil {
            log.Fatal(err)
        }

        result, _ := client.Models.GenerateContent(
            ctx,
            "gemini-2.5-flash-image",
            genai.Text("Create a modern, minimalist logo for a coffee shop called 'The Daily Grind'. The text should be in a clean, bold, sans-serif font. The design should feature a simple, stylized icon of a a coffee bean seamlessly integrated with the text. The color scheme is black and white."),
        )

        for _, part := range result.Candidates[0].Content.Parts {
            if part.Text != "" {
                fmt.Println(part.Text)
            } else if part.InlineData != nil {
                imageBytes := part.InlineData.Data
                outputFilename := "logo_example.png"
                _ = os.WriteFile(outputFilename, imageBytes, 0644)
            }
        }
    }

### REST

    curl -s -X POST
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:generateContent" \
      -H "x-goog-api-key: $GEMINI_API_KEY" \
      -H "Content-Type: application/json" \
      -d '{
        "contents": [{
          "parts": [
            {"text": "Create a modern, minimalist logo for a coffee shop called '"'"'The Daily Grind'"'"'. The text should be in a clean, bold, sans-serif font. The design should feature a simple, stylized icon of a a coffee bean seamlessly integrated with the text. The color scheme is black and white."}
          ]
        }]
      }' \
      | grep -o '"data": "[^"]*"' \
      | cut -d'"' -f4 \
      | base64 --decode > logo_example.png

![Create a modern, minimalist logo for a coffee shop called 'The Daily Grind'...](https://ai.google.dev/static/gemini-api/docs/images/logo_example.png)Create a modern, minimalist logo for a coffee shop called 'The Daily Grind'...

#### 4. Product mockups \& commercial photography

Perfect for creating clean, professional product shots for e-commerce, advertising, or branding.  

### Template

    A high-resolution, studio-lit product photograph of a [product description]
    on a [background surface/description]. The lighting is a [lighting setup,
    e.g., three-point softbox setup] to [lighting purpose]. The camera angle is
    a [angle type] to showcase [specific feature]. Ultra-realistic, with sharp
    focus on [key detail]. [Aspect ratio].

### Prompt

    A high-resolution, studio-lit product photograph of a minimalist ceramic
    coffee mug in matte black, presented on a polished concrete surface. The
    lighting is a three-point softbox setup designed to create soft, diffused
    highlights and eliminate harsh shadows. The camera angle is a slightly
    elevated 45-degree shot to showcase its clean lines. Ultra-realistic, with
    sharp focus on the steam rising from the coffee. Square image.

### Python

    from google import genai
    from google.genai import types
    from PIL import Image

    client = genai.Client()

    # Generate an image from a text prompt
    response = client.models.generate_content(
        model="gemini-2.5-flash-image",
        contents="A high-resolution, studio-lit product photograph of a minimalist ceramic coffee mug in matte black, presented on a polished concrete surface. The lighting is a three-point softbox setup designed to create soft, diffused highlights and eliminate harsh shadows. The camera angle is a slightly elevated 45-degree shot to showcase its clean lines. Ultra-realistic, with sharp focus on the steam rising from the coffee. Square image.",
    )

    image_parts = [
        part.inline_data.data
        for part in response.parts
        if part.inline_data
    ]

    if image_parts:
        image = part.as_image()
        image.save('product_mockup.png')
        image.show()

### JavaScript

    import { GoogleGenAI } from "@google/genai";
    import * as fs from "node:fs";

    async function main() {

      const ai = new GoogleGenAI({});

      const prompt =
        "A high-resolution, studio-lit product photograph of a minimalist ceramic coffee mug in matte black, presented on a polished concrete surface. The lighting is a three-point softbox setup designed to create soft, diffused highlights and eliminate harsh shadows. The camera angle is a slightly elevated 45-degree shot to showcase its clean lines. Ultra-realistic, with sharp focus on the steam rising from the coffee. Square image.";

      const response = await ai.models.generateContent({
        model: "gemini-2.5-flash-image",
        contents: prompt,
      });
      for (const part of response.parts) {
        if (part.text) {
          console.log(part.text);
        } else if (part.inlineData) {
          const imageData = part.inlineData.data;
          const buffer = Buffer.from(imageData, "base64");
          fs.writeFileSync("product_mockup.png", buffer);
          console.log("Image saved as product_mockup.png");
        }
      }
    }

    main();

### Go

    package main

    import (
        "context"
        "fmt"
        "os"
        "google.golang.org/genai"
    )

    func main() {

        ctx := context.Background()
        client, err := genai.NewClient(ctx, nil)
        if err != nil {
            log.Fatal(err)
        }

        result, _ := client.Models.GenerateContent(
            ctx,
            "gemini-2.5-flash-image",
            genai.Text("A high-resolution, studio-lit product photograph of a minimalist ceramic coffee mug in matte black, presented on a polished concrete surface. The lighting is a three-point softbox setup designed to create soft, diffused highlights and eliminate harsh shadows. The camera angle is a slightly elevated 45-degree shot to showcase its clean lines. Ultra-realistic, with sharp focus on the steam rising from the coffee. Square image."),
        )

        for _, part := range result.Candidates[0].Content.Parts {
            if part.Text != "" {
                fmt.Println(part.Text)
            } else if part.InlineData != nil {
                imageBytes := part.InlineData.Data
                outputFilename := "product_mockup.png"
                _ = os.WriteFile(outputFilename, imageBytes, 0644)
            }
        }
    }

### REST

    curl -s -X POST
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:generateContent" \
      -H "x-goog-api-key: $GEMINI_API_KEY" \
      -H "Content-Type: application/json" \
      -d '{
        "contents": [{
          "parts": [
            {"text": "A high-resolution, studio-lit product photograph of a minimalist ceramic coffee mug in matte black, presented on a polished concrete surface. The lighting is a three-point softbox setup designed to create soft, diffused highlights and eliminate harsh shadows. The camera angle is a slightly elevated 45-degree shot to showcase its clean lines. Ultra-realistic, with sharp focus on the steam rising from the coffee. Square image."}
          ]
        }]
      }' \
      | grep -o '"data": "[^"]*"' \
      | cut -d'"' -f4 \
      | base64 --decode > product_mockup.png

![A high-resolution, studio-lit product photograph of a minimalist ceramic coffee mug...](https://ai.google.dev/static/gemini-api/docs/images/product_mockup.png)A high-resolution, studio-lit product photograph of a minimalist ceramic coffee mug...

#### 5. Minimalist \& negative space design

Excellent for creating backgrounds for websites, presentations, or marketing materials where text will be overlaid.  

### Template

    A minimalist composition featuring a single [subject] positioned in the
    [bottom-right/top-left/etc.] of the frame. The background is a vast, empty
    [color] canvas, creating significant negative space. Soft, subtle lighting.
    [Aspect ratio].

### Prompt

    A minimalist composition featuring a single, delicate red maple leaf
    positioned in the bottom-right of the frame. The background is a vast, empty
    off-white canvas, creating significant negative space for text. Soft,
    diffused lighting from the top left. Square image.

### Python

    from google import genai
    from google.genai import types
    from PIL import Image

    client = genai.Client()

    # Generate an image from a text prompt
    response = client.models.generate_content(
        model="gemini-2.5-flash-image",
        contents="A minimalist composition featuring a single, delicate red maple leaf positioned in the bottom-right of the frame. The background is a vast, empty off-white canvas, creating significant negative space for text. Soft, diffused lighting from the top left. Square image.",
    )

    image_parts = [
        part.inline_data.data
        for part in response.parts
        if part.inline_data
    ]

    if image_parts:
        image = part.as_image()
        image.save('minimalist_design.png')
        image.show()

### JavaScript

    import { GoogleGenAI } from "@google/genai";
    import * as fs from "node:fs";

    async function main() {

      const ai = new GoogleGenAI({});

      const prompt =
        "A minimalist composition featuring a single, delicate red maple leaf positioned in the bottom-right of the frame. The background is a vast, empty off-white canvas, creating significant negative space for text. Soft, diffused lighting from the top left. Square image.";

      const response = await ai.models.generateContent({
        model: "gemini-2.5-flash-image",
        contents: prompt,
      });
      for (const part of response.parts) {
        if (part.text) {
          console.log(part.text);
        } else if (part.inlineData) {
          const imageData = part.inlineData.data;
          const buffer = Buffer.from(imageData, "base64");
          fs.writeFileSync("minimalist_design.png", buffer);
          console.log("Image saved as minimalist_design.png");
        }
      }
    }

    main();

### Go

    package main

    import (
        "context"
        "fmt"
        "os"
        "google.golang.org/genai"
    )

    func main() {

        ctx := context.Background()
        client, err := genai.NewClient(ctx, nil)
        if err != nil {
            log.Fatal(err)
        }

        result, _ := client.Models.GenerateContent(
            ctx,
            "gemini-2.5-flash-image",
            genai.Text("A minimalist composition featuring a single, delicate red maple leaf positioned in the bottom-right of the frame. The background is a vast, empty off-white canvas, creating significant negative space for text. Soft, diffused lighting from the top left. Square image."),
        )

        for _, part := range result.Candidates[0].Content.Parts {
            if part.Text != "" {
                fmt.Println(part.Text)
            } else if part.InlineData != nil {
                imageBytes := part.InlineData.Data
                outputFilename := "minimalist_design.png"
                _ = os.WriteFile(outputFilename, imageBytes, 0644)
            }
        }
    }

### REST

    curl -s -X POST
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:generateContent" \
      -H "x-goog-api-key: $GEMINI_API_KEY" \
      -H "Content-Type: application/json" \
      -d '{
        "contents": [{
          "parts": [
            {"text": "A minimalist composition featuring a single, delicate red maple leaf positioned in the bottom-right of the frame. The background is a vast, empty off-white canvas, creating significant negative space for text. Soft, diffused lighting from the top left. Square image."}
          ]
        }]
      }' \
      | grep -o '"data": "[^"]*"' \
      | cut -d'"' -f4 \
      | base64 --decode > minimalist_design.png

![A minimalist composition featuring a single, delicate red maple leaf...](https://ai.google.dev/static/gemini-api/docs/images/minimalist_design.png)A minimalist composition featuring a single, delicate red maple leaf...

#### 6. Sequential art (Comic panel / Storyboard)

Builds on character consistency and scene description to create panels for visual storytelling.  

### Template

    A single comic book panel in a [art style] style. In the foreground,
    [character description and action]. In the background, [setting details].
    The panel has a [dialogue/caption box] with the text "[Text]". The lighting
    creates a [mood] mood. [Aspect ratio].

### Prompt

    A single comic book panel in a gritty, noir art style with high-contrast
    black and white inks. In the foreground, a detective in a trench coat stands
    under a flickering streetlamp, rain soaking his shoulders. In the
    background, the neon sign of a desolate bar reflects in a puddle. A caption
    box at the top reads "The city was a tough place to keep secrets." The
    lighting is harsh, creating a dramatic, somber mood. Landscape.

### Python

    from google import genai
    from google.genai import types
    from PIL import Image

    client = genai.Client()

    # Generate an image from a text prompt
    response = client.models.generate_content(
        model="gemini-2.5-flash-image",
        contents="A single comic book panel in a gritty, noir art style with high-contrast black and white inks. In the foreground, a detective in a trench coat stands under a flickering streetlamp, rain soaking his shoulders. In the background, the neon sign of a desolate bar reflects in a puddle. A caption box at the top reads \"The city was a tough place to keep secrets.\" The lighting is harsh, creating a dramatic, somber mood. Landscape.",
    )

    image_parts = [
        part.inline_data.data
        for part in response.parts
        if part.inline_data
    ]

    if image_parts:
        image = part.as_image()
        image.save('comic_panel.png')
        image.show()

### JavaScript

    import { GoogleGenAI } from "@google/genai";
    import * as fs from "node:fs";

    async function main() {

      const ai = new GoogleGenAI({});

      const prompt =
        "A single comic book panel in a gritty, noir art style with high-contrast black and white inks. In the foreground, a detective in a trench coat stands under a flickering streetlamp, rain soaking his shoulders. In the background, the neon sign of a desolate bar reflects in a puddle. A caption box at the top reads \"The city was a tough place to keep secrets.\" The lighting is harsh, creating a dramatic, somber mood. Landscape.";

      const response = await ai.models.generateContent({
        model: "gemini-2.5-flash-image",
        contents: prompt,
      });
      for (const part of response.parts) {
        if (part.text) {
          console.log(part.text);
        } else if (part.inlineData) {
          const imageData = part.inlineData.data;
          const buffer = Buffer.from(imageData, "base64");
          fs.writeFileSync("comic_panel.png", buffer);
          console.log("Image saved as comic_panel.png");
        }
      }
    }

    main();

### Go

    package main

    import (
        "context"
        "fmt"
        "os"
        "google.golang.org/genai"
    )

    func main() {

        ctx := context.Background()
        client, err := genai.NewClient(ctx, nil)
        if err != nil {
            log.Fatal(err)
        }

        result, _ := client.Models.GenerateContent(
            ctx,
            "gemini-2.5-flash-image",
            genai.Text("A single comic book panel in a gritty, noir art style with high-contrast black and white inks. In the foreground, a detective in a trench coat stands under a flickering streetlamp, rain soaking his shoulders. In the background, the neon sign of a desolate bar reflects in a puddle. A caption box at the top reads \"The city was a tough place to keep secrets.\" The lighting is harsh, creating a dramatic, somber mood. Landscape."),
        )

        for _, part := range result.Candidates[0].Content.Parts {
            if part.Text != "" {
                fmt.Println(part.Text)
            } else if part.InlineData != nil {
                imageBytes := part.InlineData.Data
                outputFilename := "comic_panel.png"
                _ = os.WriteFile(outputFilename, imageBytes, 0644)
            }
        }
    }

### REST

    curl -s -X POST
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:generateContent" \
      -H "x-goog-api-key: $GEMINI_API_KEY" \
      -H "Content-Type: application/json" \
      -d '{
        "contents": [{
          "parts": [
            {"text": "A single comic book panel in a gritty, noir art style with high-contrast black and white inks. In the foreground, a detective in a trench coat stands under a flickering streetlamp, rain soaking his shoulders. In the background, the neon sign of a desolate bar reflects in a puddle. A caption box at the top reads \"The city was a tough place to keep secrets.\" The lighting is harsh, creating a dramatic, somber mood. Landscape."}
          ]
        }]
      }' \
      | grep -o '"data": "[^"]*"' \
      | cut -d'"' -f4 \
      | base64 --decode > comic_panel.png

![A single comic book panel in a gritty, noir art style...](https://ai.google.dev/static/gemini-api/docs/images/comic_panel.png)A single comic book panel in a gritty, noir art style...

### Prompts for editing images

These examples show how to provide images alongside your text prompts for editing, composition, and style transfer.

#### 1. Adding and removing elements

Provide an image and describe your change. The model will match the original image's style, lighting, and perspective.  

### Template

    Using the provided image of [subject], please [add/remove/modify] [element]
    to/from the scene. Ensure the change is [description of how the change should
    integrate].

### Prompt

    "Using the provided image of my cat, please add a small, knitted wizard hat
    on its head. Make it look like it's sitting comfortably and matches the soft
    lighting of the photo."

### Python

    from google import genai
    from google.genai import types
    from PIL import Image

    client = genai.Client()

    # Base image prompt: "A photorealistic picture of a fluffy ginger cat sitting on a wooden floor, looking directly at the camera. Soft, natural light from a window."
    image_input = Image.open('/path/to/your/cat_photo.png')
    text_input = """Using the provided image of my cat, please add a small, knitted wizard hat on its head. Make it look like it's sitting comfortably and not falling off."""

    # Generate an image from a text prompt
    response = client.models.generate_content(
        model="gemini-2.5-flash-image",
        contents=[text_input, image_input],
    )

    image_parts = [
        part.inline_data.data
        for part in response.parts
        if part.inline_data
    ]

    if image_parts:
        image = part.as_image()
        image.save('cat_with_hat.png')
        image.show()

### JavaScript

    import { GoogleGenAI } from "@google/genai";
    import * as fs from "node:fs";

    async function main() {

      const ai = new GoogleGenAI({});

      const imagePath = "/path/to/your/cat_photo.png";
      const imageData = fs.readFileSync(imagePath);
      const base64Image = imageData.toString("base64");

      const prompt = [
        { text: "Using the provided image of my cat, please add a small, knitted wizard hat on its head. Make it look like it's sitting comfortably and not falling off." },
        {
          inlineData: {
            mimeType: "image/png",
            data: base64Image,
          },
        },
      ];

      const response = await ai.models.generateContent({
        model: "gemini-2.5-flash-image",
        contents: prompt,
      });
      for (const part of response.parts) {
        if (part.text) {
          console.log(part.text);
        } else if (part.inlineData) {
          const imageData = part.inlineData.data;
          const buffer = Buffer.from(imageData, "base64");
          fs.writeFileSync("cat_with_hat.png", buffer);
          console.log("Image saved as cat_with_hat.png");
        }
      }
    }

    main();

### Go

    package main

    import (
      "context"
      "fmt"
      "os"
      "google.golang.org/genai"
    )

    func main() {

      ctx := context.Background()
      client, err := genai.NewClient(ctx, nil)
      if err != nil {
          log.Fatal(err)
      }

      imagePath := "/path/to/your/cat_photo.png"
      imgData, _ := os.ReadFile(imagePath)

      parts := []*genai.Part{
        genai.NewPartFromText("Using the provided image of my cat, please add a small, knitted wizard hat on its head. Make it look like it's sitting comfortably and not falling off."),
        &genai.Part{
          InlineData: &genai.Blob{
            MIMEType: "image/png",
            Data:     imgData,
          },
        },
      }

      contents := []*genai.Content{
        genai.NewContentFromParts(parts, genai.RoleUser),
      }

      result, _ := client.Models.GenerateContent(
          ctx,
          "gemini-2.5-flash-image",
          contents,
      )

      for _, part := range result.Candidates[0].Content.Parts {
          if part.Text != "" {
              fmt.Println(part.Text)
          } else if part.InlineData != nil {
              imageBytes := part.InlineData.Data
              outputFilename := "cat_with_hat.png"
              _ = os.WriteFile(outputFilename, imageBytes, 0644)
          }
      }
    }

### REST

    IMG_PATH=/path/to/your/cat_photo.png

    if [[ "$(base64 --version 2>&1)" = *"FreeBSD"* ]]; then
      B64FLAGS="--input"
    else
      B64FLAGS="-w0"
    fi

    IMG_BASE64=$(base64 "$B64FLAGS" "$IMG_PATH" 2>&1)

    curl -X POST \
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:generateContent" \
        -H "x-goog-api-key: $GEMINI_API_KEY" \
        -H 'Content-Type: application/json' \
        -d "{
          \"contents\": [{
            \"parts\":[
                {\"text\": \"Using the provided image of my cat, please add a small, knitted wizard hat on its head. Make it look like it's sitting comfortably and not falling off.\"},
                {
                  \"inline_data\": {
                    \"mime_type\":\"image/png\",
                    \"data\": \"$IMG_BASE64\"
                  }
                }
            ]
          }]
        }"  \
      | grep -o '"data": "[^"]*"' \
      | cut -d'"' -f4 \
      | base64 --decode > cat_with_hat.png

|---------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Input                                                   | Output                                                                                                                                                                                                                              |
| :cat:A photorealistic picture of a fluffy ginger cat... | ![Using the provided image of my cat, please add a small, knitted wizard hat...](https://ai.google.dev/static/gemini-api/docs/images/cat_with_hat.png)Using the provided image of my cat, please add a small, knitted wizard hat... |

#### 2. Inpainting (Semantic masking)

Conversationally define a "mask" to edit a specific part of an image while leaving the rest untouched.  

### Template

    Using the provided image, change only the [specific element] to [new
    element/description]. Keep everything else in the image exactly the same,
    preserving the original style, lighting, and composition.

### Prompt

    "Using the provided image of a living room, change only the blue sofa to be
    a vintage, brown leather chesterfield sofa. Keep the rest of the room,
    including the pillows on the sofa and the lighting, unchanged."

### Python

    from google import genai
    from google.genai import types
    from PIL import Image

    client = genai.Client()

    # Base image prompt: "A wide shot of a modern, well-lit living room with a prominent blue sofa in the center. A coffee table is in front of it and a large window is in the background."
    living_room_image = Image.open('/path/to/your/living_room.png')
    text_input = """Using the provided image of a living room, change only the blue sofa to be a vintage, brown leather chesterfield sofa. Keep the rest of the room, including the pillows on the sofa and the lighting, unchanged."""

    # Generate an image from a text prompt
    response = client.models.generate_content(
        model="gemini-2.5-flash-image",
        contents=[living_room_image, text_input],
    )

    image_parts = [
        part.inline_data.data
        for part in response.parts
        if part.inline_data
    ]

    if image_parts:
        image = part.as_image()
        image.save('living_room_edited.png')
        image.show()

### JavaScript

    import { GoogleGenAI } from "@google/genai";
    import * as fs from "node:fs";

    async function main() {

      const ai = new GoogleGenAI({});

      const imagePath = "/path/to/your/living_room.png";
      const imageData = fs.readFileSync(imagePath);
      const base64Image = imageData.toString("base64");

      const prompt = [
        {
          inlineData: {
            mimeType: "image/png",
            data: base64Image,
          },
        },
        { text: "Using the provided image of a living room, change only the blue sofa to be a vintage, brown leather chesterfield sofa. Keep the rest of the room, including the pillows on the sofa and the lighting, unchanged." },
      ];

      const response = await ai.models.generateContent({
        model: "gemini-2.5-flash-image",
        contents: prompt,
      });
      for (const part of response.parts) {
        if (part.text) {
          console.log(part.text);
        } else if (part.inlineData) {
          const imageData = part.inlineData.data;
          const buffer = Buffer.from(imageData, "base64");
          fs.writeFileSync("living_room_edited.png", buffer);
          console.log("Image saved as living_room_edited.png");
        }
      }
    }

    main();

### Go

    package main

    import (
      "context"
      "fmt"
      "os"
      "google.golang.org/genai"
    )

    func main() {

      ctx := context.Background()
      client, err := genai.NewClient(ctx, nil)
      if err != nil {
          log.Fatal(err)
      }

      imagePath := "/path/to/your/living_room.png"
      imgData, _ := os.ReadFile(imagePath)

      parts := []*genai.Part{
        &genai.Part{
          InlineData: &genai.Blob{
            MIMEType: "image/png",
            Data:     imgData,
          },
        },
        genai.NewPartFromText("Using the provided image of a living room, change only the blue sofa to be a vintage, brown leather chesterfield sofa. Keep the rest of the room, including the pillows on the sofa and the lighting, unchanged."),
      }

      contents := []*genai.Content{
        genai.NewContentFromParts(parts, genai.RoleUser),
      }

      result, _ := client.Models.GenerateContent(
          ctx,
          "gemini-2.5-flash-image",
          contents,
      )

      for _, part := range result.Candidates[0].Content.Parts {
          if part.Text != "" {
              fmt.Println(part.Text)
          } else if part.InlineData != nil {
              imageBytes := part.InlineData.Data
              outputFilename := "living_room_edited.png"
              _ = os.WriteFile(outputFilename, imageBytes, 0644)
          }
      }
    }

### REST

    IMG_PATH=/path/to/your/living_room.png

    if [[ "$(base64 --version 2>&1)" = *"FreeBSD"* ]]; then
      B64FLAGS="--input"
    else
      B64FLAGS="-w0"
    fi

    IMG_BASE64=$(base64 "$B64FLAGS" "$IMG_PATH" 2>&1)

    curl -X POST \
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:generateContent" \
        -H "x-goog-api-key: $GEMINI_API_KEY" \
        -H 'Content-Type: application/json' \
        -d "{
          \"contents\": [{
            \"parts\":[
                {
                  \"inline_data\": {
                    \"mime_type\":\"image/png\",
                    \"data\": \"$IMG_BASE64\"
                  }
                },
                {\"text\": \"Using the provided image of a living room, change only the blue sofa to be a vintage, brown leather chesterfield sofa. Keep the rest of the room, including the pillows on the sofa and the lighting, unchanged.\"}
            ]
          }]
        }"  \
      | grep -o '"data": "[^"]*"' \
      | cut -d'"' -f4 \
      | base64 --decode > living_room_edited.png

|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Input                                                                                                                                                                    | Output                                                                                                                                                                                                                                                                                                                          |
| ![A wide shot of a modern, well-lit living room...](https://ai.google.dev/static/gemini-api/docs/images/living_room.png)A wide shot of a modern, well-lit living room... | ![Using the provided image of a living room, change only the blue sofa to be a vintage, brown leather chesterfield sofa...](https://ai.google.dev/static/gemini-api/docs/images/living_room_edited.png)Using the provided image of a living room, change only the blue sofa to be a vintage, brown leather chesterfield sofa... |

#### 3. Style transfer

Provide an image and ask the model to recreate its content in a different artistic style.  

### Template

    Transform the provided photograph of [subject] into the artistic style of [artist/art style]. Preserve the original composition but render it with [description of stylistic elements].

### Prompt

    "Transform the provided photograph of a modern city street at night into the artistic style of Vincent van Gogh's 'Starry Night'. Preserve the original composition of buildings and cars, but render all elements with swirling, impasto brushstrokes and a dramatic palette of deep blues and bright yellows."

### Python

    from google import genai
    from google.genai import types
    from PIL import Image

    client = genai.Client()

    # Base image prompt: "A photorealistic, high-resolution photograph of a busy city street in New York at night, with bright neon signs, yellow taxis, and tall skyscrapers."
    city_image = Image.open('/path/to/your/city.png')
    text_input = """Transform the provided photograph of a modern city street at night into the artistic style of Vincent van Gogh's 'Starry Night'. Preserve the original composition of buildings and cars, but render all elements with swirling, impasto brushstrokes and a dramatic palette of deep blues and bright yellows."""

    # Generate an image from a text prompt
    response = client.models.generate_content(
        model="gemini-2.5-flash-image",
        contents=[city_image, text_input],
    )

    image_parts = [
        part.inline_data.data
        for part in response.parts
        if part.inline_data
    ]

    if image_parts:
        image = part.as_image()
        image.save('city_style_transfer.png')
        image.show()

### JavaScript

    import { GoogleGenAI } from "@google/genai";
    import * as fs from "node:fs";

    async function main() {

      const ai = new GoogleGenAI({});

      const imagePath = "/path/to/your/city.png";
      const imageData = fs.readFileSync(imagePath);
      const base64Image = imageData.toString("base64");

      const prompt = [
        {
          inlineData: {
            mimeType: "image/png",
            data: base64Image,
          },
        },
        { text: "Transform the provided photograph of a modern city street at night into the artistic style of Vincent van Gogh's 'Starry Night'. Preserve the original composition of buildings and cars, but render all elements with swirling, impasto brushstrokes and a dramatic palette of deep blues and bright yellows." },
      ];

      const response = await ai.models.generateContent({
        model: "gemini-2.5-flash-image",
        contents: prompt,
      });
      for (const part of response.parts) {
        if (part.text) {
          console.log(part.text);
        } else if (part.inlineData) {
          const imageData = part.inlineData.data;
          const buffer = Buffer.from(imageData, "base64");
          fs.writeFileSync("city_style_transfer.png", buffer);
          console.log("Image saved as city_style_transfer.png");
        }
      }
    }

    main();

### Go

    package main

    import (
      "context"
      "fmt"
      "os"
      "google.golang.org/genai"
    )

    func main() {

      ctx := context.Background()
      client, err := genai.NewClient(ctx, nil)
      if err != nil {
          log.Fatal(err)
      }

      imagePath := "/path/to/your/city.png"
      imgData, _ := os.ReadFile(imagePath)

      parts := []*genai.Part{
        &genai.Part{
          InlineData: &genai.Blob{
            MIMEType: "image/png",
            Data:     imgData,
          },
        },
        genai.NewPartFromText("Transform the provided photograph of a modern city street at night into the artistic style of Vincent van Gogh's 'Starry Night'. Preserve the original composition of buildings and cars, but render all elements with swirling, impasto brushstrokes and a dramatic palette of deep blues and bright yellows."),
      }

      contents := []*genai.Content{
        genai.NewContentFromParts(parts, genai.RoleUser),
      }

      result, _ := client.Models.GenerateContent(
          ctx,
          "gemini-2.5-flash-image",
          contents,
      )

      for _, part := range result.Candidates[0].Content.Parts {
          if part.Text != "" {
              fmt.Println(part.Text)
          } else if part.InlineData != nil {
              imageBytes := part.InlineData.Data
              outputFilename := "city_style_transfer.png"
              _ = os.WriteFile(outputFilename, imageBytes, 0644)
          }
      }
    }

### REST

    IMG_PATH=/path/to/your/city.png

    if [[ "$(base64 --version 2>&1)" = *"FreeBSD"* ]]; then
      B64FLAGS="--input"
    else
      B64FLAGS="-w0"
    fi

    IMG_BASE64=$(base64 "$B64FLAGS" "$IMG_PATH" 2>&1)

    curl -X POST \
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:generateContent" \
        -H "x-goog-api-key: $GEMINI_API_KEY" \
        -H 'Content-Type: application/json' \
        -d "{
          \"contents\": [{
            \"parts\":[
                {
                  \"inline_data\": {
                    \"mime_type\":\"image/png\",
                    \"data\": \"$IMG_BASE64\"
                  }
                },
                {\"text\": \"Transform the provided photograph of a modern city street at night into the artistic style of Vincent van Gogh's 'Starry Night'. Preserve the original composition of buildings and cars, but render all elements with swirling, impasto brushstrokes and a dramatic palette of deep blues and bright yellows.\"}
            ]
          }]
        }"  \
      | grep -o '"data": "[^"]*"' \
      | cut -d'"' -f4 \
      | base64 --decode > city_style_transfer.png

|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Input                                                                                                                                                                                                       | Output                                                                                                                                                                                                                     |
| ![A photorealistic, high-resolution photograph of a busy city street...](https://ai.google.dev/static/gemini-api/docs/images/city.png)A photorealistic, high-resolution photograph of a busy city street... | ![Transform the provided photograph of a modern city street at night...](https://ai.google.dev/static/gemini-api/docs/images/city_style_transfer.png)Transform the provided photograph of a modern city street at night... |

#### 4. Advanced composition: Combining multiple images

Provide multiple images as context to create a new, composite scene. This is perfect for product mockups or creative collages.  

### Template

    Create a new image by combining the elements from the provided images. Take
    the [element from image 1] and place it with/on the [element from image 2].
    The final image should be a [description of the final scene].

### Prompt

    "Create a professional e-commerce fashion photo. Take the blue floral dress
    from the first image and let the woman from the second image wear it.
    Generate a realistic, full-body shot of the woman wearing the dress, with
    the lighting and shadows adjusted to match the outdoor environment."

### Python

    from google import genai
    from google.genai import types
    from PIL import Image

    client = genai.Client()

    # Base image prompts:
    # 1. Dress: "A professionally shot photo of a blue floral summer dress on a plain white background, ghost mannequin style."
    # 2. Model: "Full-body shot of a woman with her hair in a bun, smiling, standing against a neutral grey studio background."
    dress_image = Image.open('/path/to/your/dress.png')
    model_image = Image.open('/path/to/your/model.png')

    text_input = """Create a professional e-commerce fashion photo. Take the blue floral dress from the first image and let the woman from the second image wear it. Generate a realistic, full-body shot of the woman wearing the dress, with the lighting and shadows adjusted to match the outdoor environment."""

    # Generate an image from a text prompt
    response = client.models.generate_content(
        model="gemini-2.5-flash-image",
        contents=[dress_image, model_image, text_input],
    )

    image_parts = [
        part.inline_data.data
        for part in response.parts
        if part.inline_data
    ]

    if image_parts:
        image = part.as_image()
        image.save('fashion_ecommerce_shot.png')
        image.show()

### JavaScript

    import { GoogleGenAI } from "@google/genai";
    import * as fs from "node:fs";

    async function main() {

      const ai = new GoogleGenAI({});

      const imagePath1 = "/path/to/your/dress.png";
      const imageData1 = fs.readFileSync(imagePath1);
      const base64Image1 = imageData1.toString("base64");
      const imagePath2 = "/path/to/your/model.png";
      const imageData2 = fs.readFileSync(imagePath2);
      const base64Image2 = imageData2.toString("base64");

      const prompt = [
        {
          inlineData: {
            mimeType: "image/png",
            data: base64Image1,
          },
        },
        {
          inlineData: {
            mimeType: "image/png",
            data: base64Image2,
          },
        },
        { text: "Create a professional e-commerce fashion photo. Take the blue floral dress from the first image and let the woman from the second image wear it. Generate a realistic, full-body shot of the woman wearing the dress, with the lighting and shadows adjusted to match the outdoor environment." },
      ];

      const response = await ai.models.generateContent({
        model: "gemini-2.5-flash-image",
        contents: prompt,
      });
      for (const part of response.parts) {
        if (part.text) {
          console.log(part.text);
        } else if (part.inlineData) {
          const imageData = part.inlineData.data;
          const buffer = Buffer.from(imageData, "base64");
          fs.writeFileSync("fashion_ecommerce_shot.png", buffer);
          console.log("Image saved as fashion_ecommerce_shot.png");
        }
      }
    }

    main();

### Go

    package main

    import (
      "context"
      "fmt"
      "os"
      "google.golang.org/genai"
    )

    func main() {

      ctx := context.Background()
      client, err := genai.NewClient(ctx, nil)
      if err != nil {
          log.Fatal(err)
      }

      imgData1, _ := os.ReadFile("/path/to/your/dress.png")
      imgData2, _ := os.ReadFile("/path/to/your/model.png")

      parts := []*genai.Part{
        &genai.Part{
          InlineData: &genai.Blob{
            MIMEType: "image/png",
            Data:     imgData1,
          },
        },
        &genai.Part{
          InlineData: &genai.Blob{
            MIMEType: "image/png",
            Data:     imgData2,
          },
        },
        genai.NewPartFromText("Create a professional e-commerce fashion photo. Take the blue floral dress from the first image and let the woman from the second image wear it. Generate a realistic, full-body shot of the woman wearing the dress, with the lighting and shadows adjusted to match the outdoor environment."),
      }

      contents := []*genai.Content{
        genai.NewContentFromParts(parts, genai.RoleUser),
      }

      result, _ := client.Models.GenerateContent(
          ctx,
          "gemini-2.5-flash-image",
          contents,
      )

      for _, part := range result.Candidates[0].Content.Parts {
          if part.Text != "" {
              fmt.Println(part.Text)
          } else if part.InlineData != nil {
              imageBytes := part.InlineData.Data
              outputFilename := "fashion_ecommerce_shot.png"
              _ = os.WriteFile(outputFilename, imageBytes, 0644)
          }
      }
    }

### REST

    IMG_PATH1=/path/to/your/dress.png
    IMG_PATH2=/path/to/your/model.png

    if [[ "$(base64 --version 2>&1)" = *"FreeBSD"* ]]; then
      B64FLAGS="--input"
    else
      B64FLAGS="-w0"
    fi

    IMG1_BASE64=$(base64 "$B64FLAGS" "$IMG_PATH1" 2>&1)
    IMG2_BASE64=$(base64 "$B64FLAGS" "$IMG_PATH2" 2>&1)

    curl -X POST \
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:generateContent" \
        -H "x-goog-api-key: $GEMINI_API_KEY" \
        -H 'Content-Type: application/json' \
        -d "{
          \"contents\": [{
            \"parts\":[
                {
                  \"inline_data\": {
                    \"mime_type\":\"image/png\",
                    \"data\": \"$IMG1_BASE64\"
                  }
                },
                {
                  \"inline_data\": {
                    \"mime_type\":\"image/png\",
                    \"data\": \"$IMG2_BASE64\"
                  }
                },
                {\"text\": \"Create a professional e-commerce fashion photo. Take the blue floral dress from the first image and let the woman from the second image wear it. Generate a realistic, full-body shot of the woman wearing the dress, with the lighting and shadows adjusted to match the outdoor environment.\"}
            ]
          }]
        }"  \
      | grep -o '"data": "[^"]*"' \
      | cut -d'"' -f4 \
      | base64 --decode > fashion_ecommerce_shot.png

|---------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Input 1                                                             | Input 2                                                                                                                                                                  | Output                                                                                                                                                                                |
| :dress:A professionally shot photo of a blue floral summer dress... | ![Full-body shot of a woman with her hair in a bun...](https://ai.google.dev/static/gemini-api/docs/images/model.png)Full-body shot of a woman with her hair in a bun... | ![Create a professional e-commerce fashion photo...](https://ai.google.dev/static/gemini-api/docs/images/fashion_ecommerce_shot.png)Create a professional e-commerce fashion photo... |

#### 5. High-fidelity detail preservation

To ensure critical details (like a face or logo) are preserved during an edit, describe them in great detail along with your edit request.  

### Template

    Using the provided images, place [element from image 2] onto [element from
    image 1]. Ensure that the features of [element from image 1] remain
    completely unchanged. The added element should [description of how the
    element should integrate].

### Prompt

    "Take the first image of the woman with brown hair, blue eyes, and a neutral
    expression. Add the logo from the second image onto her black t-shirt.
    Ensure the woman's face and features remain completely unchanged. The logo
    should look like it's naturally printed on the fabric, following the folds
    of the shirt."

### Python

    from google import genai
    from google.genai import types
    from PIL import Image

    client = genai.Client()

    # Base image prompts:
    # 1. Woman: "A professional headshot of a woman with brown hair and blue eyes, wearing a plain black t-shirt, against a neutral studio background."
    # 2. Logo: "A simple, modern logo with the letters 'G' and 'A' in a white circle."
    woman_image = Image.open('/path/to/your/woman.png')
    logo_image = Image.open('/path/to/your/logo.png')
    text_input = """Take the first image of the woman with brown hair, blue eyes, and a neutral expression. Add the logo from the second image onto her black t-shirt. Ensure the woman's face and features remain completely unchanged. The logo should look like it's naturally printed on the fabric, following the folds of the shirt."""

    # Generate an image from a text prompt
    response = client.models.generate_content(
        model="gemini-2.5-flash-image",
        contents=[woman_image, logo_image, text_input],
    )

    image_parts = [
        part.inline_data.data
        for part in response.parts
        if part.inline_data
    ]

    if image_parts:
        image = part.as_image()
        image.save('woman_with_logo.png')
        image.show()

### JavaScript

    import { GoogleGenAI } from "@google/genai";
    import * as fs from "node:fs";

    async function main() {

      const ai = new GoogleGenAI({});

      const imagePath1 = "/path/to/your/woman.png";
      const imageData1 = fs.readFileSync(imagePath1);
      const base64Image1 = imageData1.toString("base64");
      const imagePath2 = "/path/to/your/logo.png";
      const imageData2 = fs.readFileSync(imagePath2);
      const base64Image2 = imageData2.toString("base64");

      const prompt = [
        {
          inlineData: {
            mimeType: "image/png",
            data: base64Image1,
          },
        },
        {
          inlineData: {
            mimeType: "image/png",
            data: base64Image2,
          },
        },
        { text: "Take the first image of the woman with brown hair, blue eyes, and a neutral expression. Add the logo from the second image onto her black t-shirt. Ensure the woman's face and features remain completely unchanged. The logo should look like it's naturally printed on the fabric, following the folds of the shirt." },
      ];

      const response = await ai.models.generateContent({
        model: "gemini-2.5-flash-image",
        contents: prompt,
      });
      for (const part of response.parts) {
        if (part.text) {
          console.log(part.text);
        } else if (part.inlineData) {
          const imageData = part.inlineData.data;
          const buffer = Buffer.from(imageData, "base64");
          fs.writeFileSync("woman_with_logo.png", buffer);
          console.log("Image saved as woman_with_logo.png");
        }
      }
    }

    main();

### Go

    package main

    import (
      "context"
      "fmt"
      "os"
      "google.golang.org/genai"
    )

    func main() {

      ctx := context.Background()
      client, err := genai.NewClient(ctx, nil)
      if err != nil {
          log.Fatal(err)
      }

      imgData1, _ := os.ReadFile("/path/to/your/woman.png")
      imgData2, _ := os.ReadFile("/path/to/your/logo.png")

      parts := []*genai.Part{
        &genai.Part{
          InlineData: &genai.Blob{
            MIMEType: "image/png",
            Data:     imgData1,
          },
        },
        &genai.Part{
          InlineData: &genai.Blob{
            MIMEType: "image/png",
            Data:     imgData2,
          },
        },
        genai.NewPartFromText("Take the first image of the woman with brown hair, blue eyes, and a neutral expression. Add the logo from the second image onto her black t-shirt. Ensure the woman's face and features remain completely unchanged. The logo should look like it's naturally printed on the fabric, following the folds of the shirt."),
      }

      contents := []*genai.Content{
        genai.NewContentFromParts(parts, genai.RoleUser),
      }

      result, _ := client.Models.GenerateContent(
          ctx,
          "gemini-2.5-flash-image",
          contents,
      )

      for _, part := range result.Candidates[0].Content.Parts {
          if part.Text != "" {
              fmt.Println(part.Text)
          } else if part.InlineData != nil {
              imageBytes := part.InlineData.Data
              outputFilename := "woman_with_logo.png"
              _ = os.WriteFile(outputFilename, imageBytes, 0644)
          }
      }
    }

### REST

    IMG_PATH1=/path/to/your/woman.png
    IMG_PATH2=/path/to/your/logo.png

    if [[ "$(base64 --version 2>&1)" = *"FreeBSD"* ]]; then
      B64FLAGS="--input"
    else
      B64FLAGS="-w0"
    fi

    IMG1_BASE64=$(base64 "$B64FLAGS" "$IMG_PATH1" 2>&1)
    IMG2_BASE64=$(base64 "$B64FLAGS" "$IMG_PATH2" 2>&1)

    curl -X POST \
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:generateContent" \
        -H "x-goog-api-key: $GEMINI_API_KEY" \
        -H 'Content-Type: application/json' \
        -d "{
          \"contents\": [{
            \"parts\":[
                {
                  \"inline_data\": {
                    \"mime_type\":\"image/png\",
                    \"data\": \"$IMG1_BASE64\"
                  }
                },
                {
                  \"inline_data\": {
                    \"mime_type\":\"image/png\",
                    \"data\": \"$IMG2_BASE64\"
                  }
                },
                {\"text\": \"Take the first image of the woman with brown hair, blue eyes, and a neutral expression. Add the logo from the second image onto her black t-shirt. Ensure the woman's face and features remain completely unchanged. The logo should look like it's naturally printed on the fabric, following the folds of the shirt.\"}
            ]
          }]
        }"  \
      | grep -o '"data": "[^"]*"' \
      | cut -d'"' -f4 \
      | base64 --decode > woman_with_logo.png

|----------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Input 1                                                                    | Input 2                                                                                                                                                                     | Output                                                                                                                                                                                                                                                         |
| :woman:A professional headshot of a woman with brown hair and blue eyes... | ![A simple, modern logo with the letters 'G' and 'A'...](https://ai.google.dev/static/gemini-api/docs/images/logo.png)A simple, modern logo with the letters 'G' and 'A'... | ![Take the first image of the woman with brown hair, blue eyes, and a neutral expression...](https://ai.google.dev/static/gemini-api/docs/images/woman_with_logo.png)Take the first image of the woman with brown hair, blue eyes, and a neutral expression... |

### Best Practices

To elevate your results from good to great, incorporate these professional strategies into your workflow.

- **Be Hyper-Specific:**The more detail you provide, the more control you have. Instead of "fantasy armor," describe it: "ornate elven plate armor, etched with silver leaf patterns, with a high collar and pauldrons shaped like falcon wings."
- **Provide Context and Intent:** Explain the*purpose*of the image. The model's understanding of context will influence the final output. For example, "Create a logo for a high-end, minimalist skincare brand" will yield better results than just "Create a logo."
- **Iterate and Refine:**Don't expect a perfect image on the first try. Use the conversational nature of the model to make small changes. Follow up with prompts like, "That's great, but can you make the lighting a bit warmer?" or "Keep everything the same, but change the character's expression to be more serious."
- **Use Step-by-Step Instructions:**For complex scenes with many elements, break your prompt into steps. "First, create a background of a serene, misty forest at dawn. Then, in the foreground, add a moss-covered ancient stone altar. Finally, place a single, glowing sword on top of the altar."
- **Use "Semantic Negative Prompts":**Instead of saying "no cars," describe the desired scene positively: "an empty, deserted street with no signs of traffic."
- **Control the Camera:** Use photographic and cinematic language to control the composition. Terms like`wide-angle shot`,`macro shot`,`low-angle
  perspective`.

## Limitations

- For best performance, use the following languages: EN, es-MX, ja-JP, zh-CN, hi-IN.
- Image generation does not support audio or video inputs.
- The model won't always follow the exact number of image outputs that the user explicitly asks for.
- The model works best with up to 3 images as an input.
- When generating text for an image, Gemini works best if you first generate the text and then ask for an image with the text.
- Uploading images of children is not currently supported in EEA, CH, and UK.
- All generated images include a[SynthID watermark](https://ai.google.dev/responsible/docs/safeguards/synthid).

## Optional configurations

You can optionally configure the response modalities and aspect ratio of the model's output in the`config`field of`generate_content`calls.

### Output types

The model defaults to returning text and image responses (i.e.`response_modalities=['Text', 'Image']`). You can configure the response to return only images without text using`response_modalities=['Image']`.  

### Python

    response = client.models.generate_content(
        model="gemini-2.5-flash-image",
        contents=[prompt],
        config=types.GenerateContentConfig(
            response_modalities=['Image']
        )
    )

### JavaScript

    const response = await ai.models.generateContent({
        model: "gemini-2.5-flash-image",
        contents: prompt,
        config: {
            responseModalities: ['Image']
        }
      });

### Go

    result, _ := client.Models.GenerateContent(
        ctx,
        "gemini-2.5-flash-image",
        genai.Text("Create a picture of a nano banana dish in a " +
                    " fancy restaurant with a Gemini theme"),
        &genai.GenerateContentConfig{
            ResponseModalities: "Image",
        },
      )

### REST

    -d '{
      "contents": [{
        "parts": [
          {"text": "Create a picture of a nano banana dish in a fancy restaurant with a Gemini theme"}
        ]
      }],
      "generationConfig": {
        "responseModalities": ["Image"]
      }
    }' \

### Aspect ratios

The model defaults to matching the output image size to that of your input image, or otherwise generates 1:1 squares. You can control the aspect ratio of the output image using the`aspect_ratio`field under`image_config`in the response request, shown here:  

### Python

    response = client.models.generate_content(
        model="gemini-2.5-flash-image",
        contents=[prompt],
        config=types.GenerateContentConfig(
            image_config=types.ImageConfig(
                aspect_ratio="16:9",
            )
        )
    )

### JavaScript

    const response = await ai.models.generateContent({
        model: "gemini-2.5-flash-image",
        contents: prompt,
        config: {
          imageConfig: {
            aspectRatio: "16:9",
          },
        }
      });

### Go

    result, _ := client.Models.GenerateContent(
        ctx,
        "gemini-2.5-flash-image",
        genai.Text("Create a picture of a nano banana dish in a " +
                    " fancy restaurant with a Gemini theme"),
        &genai.GenerateContentConfig{
            ImageConfig: &genai.ImageConfig{
              AspectRatio: "16:9",
            },
        }
      )

### REST

    -d '{
      "contents": [{
        "parts": [
          {"text": "Create a picture of a nano banana dish in a fancy restaurant with a Gemini theme"}
        ]
      }],
      "generationConfig": {
        "imageConfig": {
          "aspectRatio": "16:9"
        }
      }
    }' \

The different ratios available and the size of the image generated are listed in this table:

| Aspect ratio | Resolution | Tokens |
|--------------|------------|--------|
| 1:1          | 1024x1024  | 1290   |
| 2:3          | 832x1248   | 1290   |
| 3:2          | 1248x832   | 1290   |
| 3:4          | 864x1184   | 1290   |
| 4:3          | 1184x864   | 1290   |
| 4:5          | 896x1152   | 1290   |
| 5:4          | 1152x896   | 1290   |
| 9:16         | 768x1344   | 1290   |
| 16:9         | 1344x768   | 1290   |
| 21:9         | 1536x672   | 1290   |

## When to use Imagen

In addition to using Gemini's built-in image generation capabilities, you can also access[Imagen](https://ai.google.dev/gemini-api/docs/imagen), our specialized image generation model, through the Gemini API.

|     Attribute     |                                                                                                                 Imagen                                                                                                                 |                                                                                                                                                                                               Gemini Native Image                                                                                                                                                                                                |
|-------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Strengths         | Most capable image generation model to date. Recommended for photorealistic images, sharper clarity, improved spelling and typography.                                                                                                 | **Default recommendation.** Unparalleled flexibility, contextual understanding, and simple, mask-free editing. Uniquely capable of multi-turn conversational editing.                                                                                                                                                                                                                                            |
| Availability      | Generally available                                                                                                                                                                                                                    | Preview (Production usage allowed)                                                                                                                                                                                                                                                                                                                                                                               |
| Latency           | **Low**. Optimized for near-real-time performance.                                                                                                                                                                                     | Higher. More computation is required for its advanced capabilities.                                                                                                                                                                                                                                                                                                                                              |
| Cost              | Cost-effective for specialized tasks. $0.02/image to $0.12/image                                                                                                                                                                       | Token-based pricing. $30 per 1 million tokens for image output (image output tokenized at 1290 tokens per image flat, up to 1024x1024px)                                                                                                                                                                                                                                                                         |
| Recommended tasks | - Image quality, photorealism, artistic detail, or specific styles (e.g., impressionism, anime) are top priorities. - Infusing branding, style, or generating logos and product designs. - Generating advanced spelling or typography. | - Interleaved text and image generation to seamlessly blend text and images. - Combine creative elements from multiple images with a single prompt. - Make highly specific edits to images, modify individual elements with simple language commands, and iteratively work on an image. - Apply a specific design or texture from one image to another while preserving the original subject's form and details. |

Imagen 4 should be your go-to model starting to generate images with Imagen. Choose Imagen 4 Ultra for advanced use-cases or when you need the best image quality (note that can only generate one image at a time).

## What's next

- Find more examples and code samples in the[cookbook guide](https://colab.sandbox.google.com/github/google-gemini/cookbook/blob/main/quickstarts/Image_out.ipynb).
- Check out the[Veo guide](https://ai.google.dev/gemini-api/docs/video)to learn how to generate videos with the Gemini API.
- To learn more about Gemini models, see[Gemini models](https://ai.google.dev/gemini-api/docs/models/gemini).

<br />

Gemini models are built to be multimodal from the ground up, unlocking a wide range of image processing and computer vision tasks including but not limited to image captioning, classification, and visual question answering without having to train specialized ML models.
| **Tip:** In addition to their general multimodal capabilities, Gemini models (2.0 and newer) offer**improved accuracy** for specific use cases like[object detection](https://ai.google.dev/gemini-api/docs/image-understanding#object-detection)and[segmentation](https://ai.google.dev/gemini-api/docs/image-understanding#segmentation), through additional training. See the[Capabilities](https://ai.google.dev/gemini-api/docs/image-understanding#capabilities)section for more details.

## Passing images to Gemini

You can provide images as input to Gemini using two methods:

- [Passing inline image data](https://ai.google.dev/gemini-api/docs/image-understanding#inline-image): Ideal for smaller files (total request size less than 20MB, including prompts).
- [Uploading images using the File API](https://ai.google.dev/gemini-api/docs/image-understanding#upload-image): Recommended for larger files or for reusing images across multiple requests.

### Passing inline image data

You can pass inline image data in the request to`generateContent`. You can provide image data as Base64 encoded strings or by reading local files directly (depending on the language).

The following example shows how to read an image from a local file and pass it to`generateContent`API for processing.  

### Python

      from google import genai
      from google.genai import types

      with open('path/to/small-sample.jpg', 'rb') as f:
          image_bytes = f.read()

      client = genai.Client()
      response = client.models.generate_content(
        model='gemini-2.5-flash',
        contents=[
          types.Part.from_bytes(
            data=image_bytes,
            mime_type='image/jpeg',
          ),
          'Caption this image.'
        ]
      )

      print(response.text)

### JavaScript

    import { GoogleGenAI } from "@google/genai";
    import * as fs from "node:fs";

    const ai = new GoogleGenAI({});
    const base64ImageFile = fs.readFileSync("path/to/small-sample.jpg", {
      encoding: "base64",
    });

    const contents = [
      {
        inlineData: {
          mimeType: "image/jpeg",
          data: base64ImageFile,
        },
      },
      { text: "Caption this image." },
    ];

    const response = await ai.models.generateContent({
      model: "gemini-2.5-flash",
      contents: contents,
    });
    console.log(response.text);

### Go

    bytes, _ := os.ReadFile("path/to/small-sample.jpg")

    parts := []*genai.Part{
      genai.NewPartFromBytes(bytes, "image/jpeg"),
      genai.NewPartFromText("Caption this image."),
    }

    contents := []*genai.Content{
      genai.NewContentFromParts(parts, genai.RoleUser),
    }

    result, _ := client.Models.GenerateContent(
      ctx,
      "gemini-2.5-flash",
      contents,
      nil,
    )

    fmt.Println(result.Text())

### REST

    IMG_PATH="/path/to/your/image1.jpg"

    if [[ "$(base64 --version 2>&1)" = *"FreeBSD"* ]]; then
    B64FLAGS="--input"
    else
    B64FLAGS="-w0"
    fi

    curl "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent" \
    -H "x-goog-api-key: $GEMINI_API_KEY" \
    -H 'Content-Type: application/json' \
    -X POST \
    -d '{
        "contents": [{
        "parts":[
            {
                "inline_data": {
                "mime_type":"image/jpeg",
                "data": "'"$(base64 $B64FLAGS $IMG_PATH)"'"
                }
            },
            {"text": "Caption this image."},
        ]
        }]
    }' 2> /dev/null

You can also fetch an image from a URL, convert it to bytes, and pass it to`generateContent`as shown in the following examples.  

### Python

    from google import genai
    from google.genai import types

    import requests

    image_path = "https://goo.gle/instrument-img"
    image_bytes = requests.get(image_path).content
    image = types.Part.from_bytes(
      data=image_bytes, mime_type="image/jpeg"
    )

    client = genai.Client()

    response = client.models.generate_content(
        model="gemini-2.5-flash",
        contents=["What is this image?", image],
    )

    print(response.text)

### JavaScript

    import { GoogleGenAI } from "@google/genai";

    async function main() {
      const ai = new GoogleGenAI({});

      const imageUrl = "https://goo.gle/instrument-img";

      const response = await fetch(imageUrl);
      const imageArrayBuffer = await response.arrayBuffer();
      const base64ImageData = Buffer.from(imageArrayBuffer).toString('base64');

      const result = await ai.models.generateContent({
        model: "gemini-2.5-flash",
        contents: [
        {
          inlineData: {
            mimeType: 'image/jpeg',
            data: base64ImageData,
          },
        },
        { text: "Caption this image." }
      ],
      });
      console.log(result.text);
    }

    main();

### Go

    package main

    import (
      "context"
      "fmt"
      "os"
      "io"
      "net/http"
      "google.golang.org/genai"
    )

    func main() {
      ctx := context.Background()
      client, err := genai.NewClient(ctx, nil)
      if err != nil {
          log.Fatal(err)
      }

      // Download the image.
      imageResp, _ := http.Get("https://goo.gle/instrument-img")

      imageBytes, _ := io.ReadAll(imageResp.Body)

      parts := []*genai.Part{
        genai.NewPartFromBytes(imageBytes, "image/jpeg"),
        genai.NewPartFromText("Caption this image."),
      }

      contents := []*genai.Content{
        genai.NewContentFromParts(parts, genai.RoleUser),
      }

      result, _ := client.Models.GenerateContent(
        ctx,
        "gemini-2.5-flash",
        contents,
        nil,
      )

      fmt.Println(result.Text())
    }

### REST

    IMG_URL="https://goo.gle/instrument-img"

    MIME_TYPE=$(curl -sIL "$IMG_URL" | grep -i '^content-type:' | awk -F ': ' '{print $2}' | sed 's/\r$//' | head -n 1)
    if [[ -z "$MIME_TYPE" || ! "$MIME_TYPE" == image/* ]]; then
      MIME_TYPE="image/jpeg"
    fi

    # Check for macOS
    if [[ "$(uname)" == "Darwin" ]]; then
      IMAGE_B64=$(curl -sL "$IMG_URL" | base64 -b 0)
    elif [[ "$(base64 --version 2>&1)" = *"FreeBSD"* ]]; then
      IMAGE_B64=$(curl -sL "$IMG_URL" | base64)
    else
      IMAGE_B64=$(curl -sL "$IMG_URL" | base64 -w0)
    fi

    curl "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent" \
        -H "x-goog-api-key: $GEMINI_API_KEY" \
        -H 'Content-Type: application/json' \
        -X POST \
        -d '{
          "contents": [{
            "parts":[
                {
                  "inline_data": {
                    "mime_type":"'"$MIME_TYPE"'",
                    "data": "'"$IMAGE_B64"'"
                  }
                },
                {"text": "Caption this image."}
            ]
          }]
        }' 2> /dev/null

| **Note:** Inline image data limits your total request size (text prompts, system instructions, and inline bytes) to 20MB. For larger requests,[upload image files](https://ai.google.dev/gemini-api/docs/image-understanding#upload-image)using the File API. Files API is also more efficient for scenarios that use the same image repeatedly.

### Uploading images using the File API

For large files or to be able to use the same image file repeatedly, use the Files API. The following code uploads an image file and then uses the file in a call to`generateContent`. See the[Files API guide](https://ai.google.dev/gemini-api/docs/files)for more information and examples.  

### Python

    from google import genai

    client = genai.Client()

    my_file = client.files.upload(file="path/to/sample.jpg")

    response = client.models.generate_content(
        model="gemini-2.5-flash",
        contents=[my_file, "Caption this image."],
    )

    print(response.text)

### JavaScript

    import {
      GoogleGenAI,
      createUserContent,
      createPartFromUri,
    } from "@google/genai";

    const ai = new GoogleGenAI({});

    async function main() {
      const myfile = await ai.files.upload({
        file: "path/to/sample.jpg",
        config: { mimeType: "image/jpeg" },
      });

      const response = await ai.models.generateContent({
        model: "gemini-2.5-flash",
        contents: createUserContent([
          createPartFromUri(myfile.uri, myfile.mimeType),
          "Caption this image.",
        ]),
      });
      console.log(response.text);
    }

    await main();

### Go

    package main

    import (
      "context"
      "fmt"
      "os"
      "google.golang.org/genai"
    )

    func main() {
      ctx := context.Background()
      client, err := genai.NewClient(ctx, nil)
      if err != nil {
          log.Fatal(err)
      }

      uploadedFile, _ := client.Files.UploadFromPath(ctx, "path/to/sample.jpg", nil)

      parts := []*genai.Part{
          genai.NewPartFromText("Caption this image."),
          genai.NewPartFromURI(uploadedFile.URI, uploadedFile.MIMEType),
      }

      contents := []*genai.Content{
          genai.NewContentFromParts(parts, genai.RoleUser),
      }

      result, _ := client.Models.GenerateContent(
          ctx,
          "gemini-2.5-flash",
          contents,
          nil,
      )

      fmt.Println(result.Text())
    }

### REST

    IMAGE_PATH="path/to/sample.jpg"
    MIME_TYPE=$(file -b --mime-type "${IMAGE_PATH}")
    NUM_BYTES=$(wc -c < "${IMAGE_PATH}")
    DISPLAY_NAME=IMAGE

    tmp_header_file=upload-header.tmp

    # Initial resumable request defining metadata.
    # The upload url is in the response headers dump them to a file.
    curl "https://generativelanguage.googleapis.com/upload/v1beta/files" \
      -H "x-goog-api-key: $GEMINI_API_KEY" \
      -D upload-header.tmp \
      -H "X-Goog-Upload-Protocol: resumable" \
      -H "X-Goog-Upload-Command: start" \
      -H "X-Goog-Upload-Header-Content-Length: ${NUM_BYTES}" \
      -H "X-Goog-Upload-Header-Content-Type: ${MIME_TYPE}" \
      -H "Content-Type: application/json" \
      -d "{'file': {'display_name': '${DISPLAY_NAME}'}}" 2> /dev/null

    upload_url=$(grep -i "x-goog-upload-url: " "${tmp_header_file}" | cut -d" " -f2 | tr -d "\r")
    rm "${tmp_header_file}"

    # Upload the actual bytes.
    curl "${upload_url}" \
      -H "x-goog-api-key: $GEMINI_API_KEY" \
      -H "Content-Length: ${NUM_BYTES}" \
      -H "X-Goog-Upload-Offset: 0" \
      -H "X-Goog-Upload-Command: upload, finalize" \
      --data-binary "@${IMAGE_PATH}" 2> /dev/null > file_info.json

    file_uri=$(jq -r ".file.uri" file_info.json)
    echo file_uri=$file_uri

    # Now generate content using that file
    curl "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent" \
        -H "x-goog-api-key: $GEMINI_API_KEY" \
        -H 'Content-Type: application/json' \
        -X POST \
        -d '{
          "contents": [{
            "parts":[
              {"file_data":{"mime_type": "'"${MIME_TYPE}"'", "file_uri": "'"${file_uri}"'"}},
              {"text": "Caption this image."}]
            }]
          }' 2> /dev/null > response.json

    cat response.json
    echo

    jq ".candidates[].content.parts[].text" response.json

## Prompting with multiple images

You can provide multiple images in a single prompt by including multiple image`Part`objects in the`contents`array. These can be a mix of inline data (local files or URLs) and File API references.  

### Python

    from google import genai
    from google.genai import types

    client = genai.Client()

    # Upload the first image
    image1_path = "path/to/image1.jpg"
    uploaded_file = client.files.upload(file=image1_path)

    # Prepare the second image as inline data
    image2_path = "path/to/image2.png"
    with open(image2_path, 'rb') as f:
        img2_bytes = f.read()

    # Create the prompt with text and multiple images
    response = client.models.generate_content(

        model="gemini-2.5-flash",
        contents=[
            "What is different between these two images?",
            uploaded_file,  # Use the uploaded file reference
            types.Part.from_bytes(
                data=img2_bytes,
                mime_type='image/png'
            )
        ]
    )

    print(response.text)

### JavaScript

    import {
      GoogleGenAI,
      createUserContent,
      createPartFromUri,
    } from "@google/genai";
    import * as fs from "node:fs";

    const ai = new GoogleGenAI({});

    async function main() {
      // Upload the first image
      const image1_path = "path/to/image1.jpg";
      const uploadedFile = await ai.files.upload({
        file: image1_path,
        config: { mimeType: "image/jpeg" },
      });

      // Prepare the second image as inline data
      const image2_path = "path/to/image2.png";
      const base64Image2File = fs.readFileSync(image2_path, {
        encoding: "base64",
      });

      // Create the prompt with text and multiple images

      const response = await ai.models.generateContent({

        model: "gemini-2.5-flash",
        contents: createUserContent([
          "What is different between these two images?",
          createPartFromUri(uploadedFile.uri, uploadedFile.mimeType),
          {
            inlineData: {
              mimeType: "image/png",
              data: base64Image2File,
            },
          },
        ]),
      });
      console.log(response.text);
    }

    await main();

### Go

    // Upload the first image
    image1Path := "path/to/image1.jpg"
    uploadedFile, _ := client.Files.UploadFromPath(ctx, image1Path, nil)

    // Prepare the second image as inline data
    image2Path := "path/to/image2.jpeg"
    imgBytes, _ := os.ReadFile(image2Path)

    parts := []*genai.Part{
      genai.NewPartFromText("What is different between these two images?"),
      genai.NewPartFromBytes(imgBytes, "image/jpeg"),
      genai.NewPartFromURI(uploadedFile.URI, uploadedFile.MIMEType),
    }

    contents := []*genai.Content{
      genai.NewContentFromParts(parts, genai.RoleUser),
    }

    result, _ := client.Models.GenerateContent(
      ctx,
      "gemini-2.5-flash",
      contents,
      nil,
    )

    fmt.Println(result.Text())

### REST

    # Upload the first image
    IMAGE1_PATH="path/to/image1.jpg"
    MIME1_TYPE=$(file -b --mime-type "${IMAGE1_PATH}")
    NUM1_BYTES=$(wc -c < "${IMAGE1_PATH}")
    DISPLAY_NAME1=IMAGE1

    tmp_header_file1=upload-header1.tmp

    curl "https://generativelanguage.googleapis.com/upload/v1beta/files" \
      -H "x-goog-api-key: $GEMINI_API_KEY" \
      -D upload-header1.tmp \
      -H "X-Goog-Upload-Protocol: resumable" \
      -H "X-Goog-Upload-Command: start" \
      -H "X-Goog-Upload-Header-Content-Length: ${NUM1_BYTES}" \
      -H "X-Goog-Upload-Header-Content-Type: ${MIME1_TYPE}" \
      -H "Content-Type: application/json" \
      -d "{'file': {'display_name': '${DISPLAY_NAME1}'}}" 2> /dev/null

    upload_url1=$(grep -i "x-goog-upload-url: " "${tmp_header_file1}" | cut -d" " -f2 | tr -d "\r")
    rm "${tmp_header_file1}"

    curl "${upload_url1}" \
      -H "Content-Length: ${NUM1_BYTES}" \
      -H "X-Goog-Upload-Offset: 0" \
      -H "X-Goog-Upload-Command: upload, finalize" \
      --data-binary "@${IMAGE1_PATH}" 2> /dev/null > file_info1.json

    file1_uri=$(jq ".file.uri" file_info1.json)
    echo file1_uri=$file1_uri

    # Prepare the second image (inline)
    IMAGE2_PATH="path/to/image2.png"
    MIME2_TYPE=$(file -b --mime-type "${IMAGE2_PATH}")

    if [[ "$(base64 --version 2>&1)" = *"FreeBSD"* ]]; then
      B64FLAGS="--input"
    else
      B64FLAGS="-w0"
    fi
    IMAGE2_BASE64=$(base64 $B64FLAGS $IMAGE2_PATH)

    # Now generate content using both images
    curl "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent" \
        -H "x-goog-api-key: $GEMINI_API_KEY" \
        -H 'Content-Type: application/json' \
        -X POST \
        -d '{
          "contents": [{
            "parts":[
              {"text": "What is different between these two images?"},
              {"file_data":{"mime_type": "'"${MIME1_TYPE}"'", "file_uri": '$file1_uri'}},
              {
                "inline_data": {
                  "mime_type":"'"${MIME2_TYPE}"'",
                  "data": "'"$IMAGE2_BASE64"'"
                }
              }
            ]
          }]
        }' 2> /dev/null > response.json

    cat response.json
    echo

    jq ".candidates[].content.parts[].text" response.json

## Object detection

From Gemini 2.0 onwards, models are further trained to detect objects in an image and get their bounding box coordinates. The coordinates, relative to image dimensions, scale to \[0, 1000\]. You need to descale these coordinates based on your original image size.  

### Python

    from google import genai
    from google.genai import types
    from PIL import Image
    import json

    client = genai.Client()
    prompt = "Detect the all of the prominent items in the image. The box_2d should be [ymin, xmin, ymax, xmax] normalized to 0-1000."

    image = Image.open("/path/to/image.png")

    config = types.GenerateContentConfig(
      response_mime_type="application/json"
      )

    response = client.models.generate_content(model="gemini-2.5-flash",
                                              contents=[image, prompt],
                                              config=config
                                              )

    width, height = image.size
    bounding_boxes = json.loads(response.text)

    converted_bounding_boxes = []
    for bounding_box in bounding_boxes:
        abs_y1 = int(bounding_box["box_2d"][0]/1000 * height)
        abs_x1 = int(bounding_box["box_2d"][1]/1000 * width)
        abs_y2 = int(bounding_box["box_2d"][2]/1000 * height)
        abs_x2 = int(bounding_box["box_2d"][3]/1000 * width)
        converted_bounding_boxes.append([abs_x1, abs_y1, abs_x2, abs_y2])

    print("Image size: ", width, height)
    print("Bounding boxes:", converted_bounding_boxes)

| **Note:** The model also supports generating bounding boxes based on custom instructions, such as: "Show bounding boxes of all green objects in this image". It also support custom labels like "label the items with the allergens they can contain".

For more examples, check following notebooks in the[Gemini Cookbook](https://github.com/google-gemini/cookbook):

- [2D spatial understanding notebook](https://colab.research.google.com/github/google-gemini/cookbook/blob/main/quickstarts/Spatial_understanding.ipynb)
- [Experimental 3D pointing notebook](https://colab.research.google.com/github/google-gemini/cookbook/blob/main/examples/Spatial_understanding_3d.ipynb)

## Segmentation

Starting with Gemini 2.5, models not only detect items but also segment them and provide their contour masks.

The model predicts a JSON list, where each item represents a segmentation mask. Each item has a bounding box ("`box_2d`") in the format`[y0, x0, y1, x1]`with normalized coordinates between 0 and 1000, a label ("`label`") that identifies the object, and finally the segmentation mask inside the bounding box, as base64 encoded png that is a probability map with values between 0 and 255. The mask needs to be resized to match the bounding box dimensions, then binarized at your confidence threshold (127 for the midpoint).
**Note:** For better results, disable[thinking](https://ai.google.dev/gemini-api/docs/thinking)by setting the thinking budget to 0. See code sample below for an example.  

### Python

    from google import genai
    from google.genai import types
    from PIL import Image, ImageDraw
    import io
    import base64
    import json
    import numpy as np
    import os

    client = genai.Client()

    def parse_json(json_output: str):
      # Parsing out the markdown fencing
      lines = json_output.splitlines()
      for i, line in enumerate(lines):
        if line == "```json":
          json_output = "\n".join(lines[i+1:])  # Remove everything before "```json"
          output = json_output.split("```")[0]  # Remove everything after the closing "```"
          break  # Exit the loop once "```json" is found
      return json_output

    def extract_segmentation_masks(image_path: str, output_dir: str = "segmentation_outputs"):
      # Load and resize image
      im = Image.open(image_path)
      im.thumbnail([1024, 1024], Image.Resampling.LANCZOS)

      prompt = """
      Give the segmentation masks for the wooden and glass items.
      Output a JSON list of segmentation masks where each entry contains the 2D
      bounding box in the key "box_2d", the segmentation mask in key "mask", and
      the text label in the key "label". Use descriptive labels.
      """

      config = types.GenerateContentConfig(
        thinking_config=types.ThinkingConfig(thinking_budget=0) # set thinking_budget to 0 for better results in object detection
      )

      response = client.models.generate_content(
        model="gemini-2.5-flash",
        contents=[prompt, im], # Pillow images can be directly passed as inputs (which will be converted by the SDK)
        config=config
      )

      # Parse JSON response
      items = json.loads(parse_json(response.text))

      # Create output directory
      os.makedirs(output_dir, exist_ok=True)

      # Process each mask
      for i, item in enumerate(items):
          # Get bounding box coordinates
          box = item["box_2d"]
          y0 = int(box[0] / 1000 * im.size[1])
          x0 = int(box[1] / 1000 * im.size[0])
          y1 = int(box[2] / 1000 * im.size[1])
          x1 = int(box[3] / 1000 * im.size[0])

          # Skip invalid boxes
          if y0 >= y1 or x0 >= x1:
              continue

          # Process mask
          png_str = item["mask"]
          if not png_str.startswith("data:image/png;base64,"):
              continue

          # Remove prefix
          png_str = png_str.removeprefix("data:image/png;base64,")
          mask_data = base64.b64decode(png_str)
          mask = Image.open(io.BytesIO(mask_data))

          # Resize mask to match bounding box
          mask = mask.resize((x1 - x0, y1 - y0), Image.Resampling.BILINEAR)

          # Convert mask to numpy array for processing
          mask_array = np.array(mask)

          # Create overlay for this mask
          overlay = Image.new('RGBA', im.size, (0, 0, 0, 0))
          overlay_draw = ImageDraw.Draw(overlay)

          # Create overlay for the mask
          color = (255, 255, 255, 200)
          for y in range(y0, y1):
              for x in range(x0, x1):
                  if mask_array[y - y0, x - x0] > 128:  # Threshold for mask
                      overlay_draw.point((x, y), fill=color)

          # Save individual mask and its overlay
          mask_filename = f"{item['label']}_{i}_mask.png"
          overlay_filename = f"{item['label']}_{i}_overlay.png"

          mask.save(os.path.join(output_dir, mask_filename))

          # Create and save overlay
          composite = Image.alpha_composite(im.convert('RGBA'), overlay)
          composite.save(os.path.join(output_dir, overlay_filename))
          print(f"Saved mask and overlay for {item['label']} to {output_dir}")

    # Example usage
    if __name__ == "__main__":
      extract_segmentation_masks("path/to/image.png")

Check the[segmentation example](https://colab.research.google.com/github/google-gemini/cookbook/blob/main/quickstarts/Spatial_understanding.ipynb#scrollTo=WQJTJ8wdGOKx)in the cookbook guide for a more detailed example.
![A table with cupcakes, with the wooden and glass objects highlighted](https://ai.google.dev/static/gemini-api/docs/images/segmentation.jpg)An example segmentation output with objects and segmentation masks

## Supported image formats

Gemini supports the following image format MIME types:

- PNG -`image/png`
- JPEG -`image/jpeg`
- WEBP -`image/webp`
- HEIC -`image/heic`
- HEIF -`image/heif`

## Capabilities

All Gemini model versions are multimodal and can be utilized in a wide range of image processing and computer vision tasks including but not limited to image captioning, visual question and answering, image classification, object detection and segmentation.

Gemini can reduce the need to use specialized ML models depending on your quality and performance requirements.

Some later model versions are specifically trained improve accuracy of specialized tasks in addition to generic capabilities:

- **Gemini 2.0 models** are further trained to support enhanced[object detection](https://ai.google.dev/gemini-api/docs/image-understanding#object-detection).

- **Gemini 2.5 models** are further trained to support enhanced[segmentation](https://ai.google.dev/gemini-api/docs/image-understanding#segmentation)in addition to[object detection](https://ai.google.dev/gemini-api/docs/image-understanding#object-detection).

## Limitations and key technical information

### File limit

Gemini 2.5 Pro/Flash, 2.0 Flash, 1.5 Pro, and 1.5 Flash support a maximum of 3,600 image files per request.

### Token calculation

- **Gemini 1.5 Flash and Gemini 1.5 Pro**: 258 tokens if both dimensions \<= 384 pixels. Larger images are tiled (min tile 256px, max 768px, resized to 768x768), with each tile costing 258 tokens.
- **Gemini 2.0 Flash and Gemini 2.5 Flash/Pro**: 258 tokens if both dimensions \<= 384 pixels. Larger images are tiled into 768x768 pixel tiles, each costing 258 tokens.

A rough formula for calculating the number of tiles is as follows:

- Calculate the crop unit size which is roughly: floor(min(width, height) / 1.5).
- Divide each dimension by the crop unit size and multiply together to get the number of tiles.

For example, for an image of dimensions 960x540 would have a crop unit size of 360. Divide each dimension by 360 and the number of tile is 3 \* 2 = 6.

### Media resolution

Gemini 3 introduces granular control over multimodal vision processing with the`media_resolution`parameter. The`media_resolution`parameter determines the**maximum number of tokens allocated per input image or video frame.**Higher resolutions improve the model's ability to read fine text or identify small details, but increase token usage and latency.

For more details about the parameter and how it can impact token calculations, see the[media resolution](https://ai.google.dev/gemini-api/docs/media-resolution)guide.

## Tips and best practices

- Verify that images are correctly rotated.
- Use clear, non-blurry images.
- When using a single image with text, place the text prompt*after* the image part in the`contents`array.

## What's next

This guide shows you how to upload image files and generate text outputs from image inputs. To learn more, see the following resources:

- [Files API](https://ai.google.dev/gemini-api/docs/files): Learn more about uploading and managing files for use with Gemini.
- [System instructions](https://ai.google.dev/gemini-api/docs/text-generation#system-instructions): System instructions let you steer the behavior of the model based on your specific needs and use cases.
- [File prompting strategies](https://ai.google.dev/gemini-api/docs/files#prompt-guide): The Gemini API supports prompting with text, image, audio, and video data, also known as multimodal prompting.
- [Safety guidance](https://ai.google.dev/gemini-api/docs/safety-guidance): Sometimes generative AI models produce unexpected outputs, such as outputs that are inaccurate, biased, or offensive. Post-processing and human evaluation are essential to limit the risk of harm from such outputs.