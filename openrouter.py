from openai import OpenAI
client = OpenAI(
  base_url="https://openrouter.ai/api/v1",
  api_key="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",
)
completion = client.chat.completions.create(
  extra_headers={
  },
  model="openai/gpt-4o",
  messages=[
    {
      "role": "user",
      "content": "What is the meaning of life?"
    }
  ]
)
print(completion.choices[0].message.content)
