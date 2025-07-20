import requests
import json
import os

def query_openrouter():
    """
    Sends a chat completion request to the OpenRouter API using the requests library.
    """
    # It's highly recommended to set your API key as an environment variable
    # for security purposes, rather than hardcoding it in the script.
    # Example: export OPENROUTER_API_KEY='your_key_here'
    api_key = os.getenv("OPENROUTER_API_KEY")

    if not api_key:
        print("Error: OPENROUTER_API_KEY environment variable not set.")
        return

    try:
        response = requests.post(
            url="https://openrouter.ai/api/v1/chat/completions",
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json" # Ensure the server knows we're sending JSON
            },
            data=json.dumps({
                "model": "openai/gpt-4o",
                "messages": [
                    {
                        "role": "user",
                        "content": "What is the meaning of life?"
                    }
                ]
            })
        )

        # Raise an exception for bad status codes (4xx or 5xx)
        response.raise_for_status()

        # Parse the JSON response
        completion = response.json()
        print(completion)

        # Extract and print the content from the first choice
        if completion.get("choices"):
            message_content = completion["choices"][0]["message"]["content"]
            print(message_content)
        else:
            print("Error: The response did not contain 'choices'.")
            print("Full response:", completion)

    except requests.exceptions.RequestException as e:
        print(f"An error occurred with the API request: {e}")
    except json.JSONDecodeError:
        print("Error: Failed to decode JSON from the response.")
        print("Raw response text:", response.text)
    except KeyError:
        print("Error: Unexpected response format from the API.")
        print("Full response:", response.json())


if __name__ == "__main__":
    query_openrouter()
