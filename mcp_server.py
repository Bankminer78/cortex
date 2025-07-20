#!/usr/bin/env python3
"""
MCP Server for Cortex - Provides OS interaction functions for productivity monitoring
"""

import asyncio
import json
import sys
from typing import Any, Dict, List
import subprocess
import os

# MCP imports
from mcp.server import Server
from mcp.server.models import InitializationOptions
from mcp.server.stdio import stdio_server
from mcp.types import Resource, Tool, TextContent, ImageContent, EmbeddedResource

# Initialize the MCP server
server = Server("cortex-os-server")

@server.list_tools()
async def handle_list_tools() -> List[Tool]:
    """
    List available tools that the LLM can call
    """
    return [
        Tool(
            name="show_popup",
            description="Display a popup warning to the user about unproductive activity",
            inputSchema={
                "type": "object",
                "properties": {
                    "title": {
                        "type": "string",
                        "description": "Title of the popup (e.g., 'Productivity Alert')"
                    },
                    "message": {
                        "type": "string", 
                        "description": "Warning message to display (e.g., 'You are browsing Instagram. Consider returning to your goal.')"
                    },
                    "severity": {
                        "type": "string",
                        "enum": ["info", "warning", "critical"],
                        "description": "Severity level of the alert",
                        "default": "warning"
                    }
                },
                "required": ["title", "message"]
            }
        ),
        Tool(
            name="log_activity",
            description="Log user activity for tracking purposes",
            inputSchema={
                "type": "object",
                "properties": {
                    "activity": {
                        "type": "string",
                        "description": "Description of the user's current activity"
                    },
                    "productive": {
                        "type": "boolean",
                        "description": "Whether the activity is considered productive"
                    },
                    "app_name": {
                        "type": "string",
                        "description": "Name of the application being used"
                    }
                },
                "required": ["activity", "productive"]
            }
        )
    ]

@server.call_tool()
async def handle_call_tool(name: str, arguments: Dict[str, Any]) -> List[TextContent]:
    """
    Handle tool calls from the LLM
    """
    
    if name == "show_popup":
        title = arguments.get("title", "Productivity Alert")
        message = arguments.get("message", "Please return to your productive work")
        severity = arguments.get("severity", "warning")
        
        try:
            # Use AppleScript to show native macOS popup
            applescript = f'''
            display alert "{title}" message "{message}" as {severity} giving up after 10
            '''
            
            result = subprocess.run(
                ["osascript", "-e", applescript],
                capture_output=True,
                text=True,
                timeout=15
            )
            
            if result.returncode == 0:
                return [TextContent(
                    type="text", 
                    text=f"Popup displayed successfully: '{title}' - '{message}'"
                )]
            else:
                return [TextContent(
                    type="text", 
                    text=f"Failed to display popup: {result.stderr}"
                )]
                
        except subprocess.TimeoutExpired:
            return [TextContent(
                type="text", 
                text="Popup display timed out"
            )]
        except Exception as e:
            return [TextContent(
                type="text", 
                text=f"Error displaying popup: {str(e)}"
            )]
    
    elif name == "log_activity":
        activity = arguments.get("activity", "Unknown activity")
        productive = arguments.get("productive", False)
        app_name = arguments.get("app_name", "Unknown app")
        
        # Log to file for tracking
        log_entry = {
            "timestamp": asyncio.get_event_loop().time(),
            "activity": activity,
            "productive": productive,
            "app_name": app_name
        }
        
        try:
            log_dir = os.path.expanduser("~/Library/Logs/Cortex")
            os.makedirs(log_dir, exist_ok=True)
            
            with open(f"{log_dir}/activity.log", "a") as f:
                f.write(json.dumps(log_entry) + "\n")
                
            return [TextContent(
                type="text",
                text=f"Activity logged: {activity} ({'productive' if productive else 'unproductive'}) in {app_name}"
            )]
            
        except Exception as e:
            return [TextContent(
                type="text",
                text=f"Failed to log activity: {str(e)}"
            )]
    
    else:
        return [TextContent(
            type="text", 
            text=f"Unknown tool: {name}"
        )]

@server.list_resources()
async def handle_list_resources() -> List[Resource]:
    """
    List available resources (none for now, but required for MCP)
    """
    return []

@server.read_resource()
async def handle_read_resource(uri: str) -> str:
    """
    Read resource content (none for now, but required for MCP)
    """
    return ""

async def main():
    """
    Main function to run the MCP server
    """
    async with stdio_server() as (read_stream, write_stream):
        await server.run(
            read_stream,
            write_stream,
            InitializationOptions(
                server_name="cortex-os-server",
                server_version="1.0.0",
                capabilities=server.get_capabilities(
                    notification_options=None,
                    experimental_capabilities=None,
                ),
            ),
        )

if __name__ == "__main__":
    asyncio.run(main())