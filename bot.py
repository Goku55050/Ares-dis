import discord
from discord.ext import commands
import asyncio
import os
from flask import Flask
from threading import Thread

# --- RENDER KEEP-ALIVE SERVER ---
app = Flask('')

@app.route('/')
def home():
    return "Bot is online!"

def run():
    # Render uses the PORT environment variable
    port = int(os.environ.get("PORT", 8080))
    app.run(host='0.0.0.0', port=port)

def keep_alive():
    t = Thread(target=run)
    t.start()

# --- CONFIGURATION ---
# Add all your bot tokens to this list
TOKENS = [
    'MTQ5Mzk2NzExODU5NTUyNjcwNw.GWAOs5.Rx5Zdxw4hUBjt-li3aUU7RoKYAK0tJ7XhI5liw',
    # 'ANOTHER_TOKEN_HERE',
] 

PREFIX = '!'

# Authorized Owner IDs
MY_OWNER_IDS = [873940090248896522, 1489661409251033149, 1492170819722281010]

# Setup Intents
intents = discord.Intents.default()
intents.message_content = True 

class MyBot(commands.Bot):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.is_blasting = False

    async def on_ready(self):
        print(f'✅ Logged in as {self.user.name}')
        print(f'🔒 Authorized Owner IDs: {MY_OWNER_IDS}')
        print(f'--- {self.user.name} is online and ready ---')

    async def setup_hook(self):
        # Add commands to this specific instance
        self.add_command(blast)
        self.add_command(stop)

@commands.command()
async def blast(ctx, delay: int, *, target: str):
    # SECURITY CHECK: Only authorized IDs can trigger this
    if ctx.author.id not in MY_OWNER_IDS:
        return

    if ctx.bot.is_blasting:
        await ctx.send(f"⚠️ [{ctx.bot.user.name}] A blast sequence is already running! Use `!stop` first.")
        return

    ctx.bot.is_blasting = True
    
    messages = [
        f"{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄🤣_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．　　　　．　　　　．　　　．　　　　　　．　　　　　_　　　　　　　_　　　　　_🤣{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄🤣_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．　　　　．　　　　．　　　．　　　　　　．　　　　　_　　　　　　　_　　　　　_🤣{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄🤣_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．　　　　．　　　　．　　　．　　　　　　．　　　　　_　　　　　　　_　　　　　_🤣{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄🤣_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．　　　　．　　　　．　　　．　　　　　　．　　　　　_　　　　　　　_　　　　　_🤣{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄🤣_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．",
        f"{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄😍_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．　　　　．　　　　．　　　．　　　　　　．　　　　　_　　　　　　　_　　　　　_😍{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄😍_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．　　　　．　　　　．　　　．　　　　　　．　　　　　_　　　　　　　_　　　　　_😍{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄😍_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．　　　　．　　　　．　　　．　　　　　　．　　　　　_　　　　　　　_　　　　　_😍{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄😍_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．　　　　．　　　　．　　　．　　　　　　．　　　　　_　　　　　　　_　　　　　_😍{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄😍_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．",
        f"{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄🥵_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．　　　　．　　　　．　　　．　　　　　　．　　　　　_　　　　　　　_　　　　　_🥵{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄🥵_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．　　　　．　　　　．　　　．　　　　　　．　　　　　_　　　　　　　_　　　　　_🥵{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄🥵_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．　　　　．　　　　．　　　．　　　　　　．　　　　　_　　　　　_🥵{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄🥵_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．　　　　．　　　　．　　　．　　　　　　．　　　　　_　　　　　　　_　　　　　_🥵{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄🥵_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．",
        f"{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄😡_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．　　　　．　　　　．　　　．　　　　　　．　　　　　_　　　　　　　_　　　　　_😡{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄😡_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．　　　　．　　　　．　　　．　　　　　　．　　　　　_　　　　　　　_　　　　　_😡{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄😡_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．　　　　．　　　　．　　　．　　　　　　．　　　　　_　　　　　　　_　　　　　_😡{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄😡_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．　　　　．　　　　．　　　．　　　　　　．　　　　　_　　　　　　　_　　　　　_😡{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄😡_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．",
        f"{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄😝_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．　　　　．　　　　．　　　．　　　　　　．　　　　　_　　　　　　　_　　　　　_😝{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄😝_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．　　　　．　　　　．　　　．　　　　　　．　　　　　_　　　　　　　_　　　　　_😝{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄😝_　　　　　_😝{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄😝_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．　　　　．　　　　．　　　．　　　　　　．　　　　　_　　　　　　　_　　　　　_😝{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄😝_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．",
        f"{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄🥳_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．　　　　．　　　　．　　　．　　　　　_　　　　　　　_　　　　　_🥳{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄🥳_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．　　　　．　　　　．　　　．　　　　　　．　　　　　_　　　　　　　_　　　　　_🥳{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄🥳_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．　　　　．　　　　．　　　．　　　　　　．　　　　　_　　　　　　　_　　　　　_🥳{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄🥳_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．　　　　．　　　　．　　　．　　　　　　．　　　　　_　　　　　　　_　　　　　_🥳{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄🥳_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．",
        f"{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄😭_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．　　　　．　　　　．　　　．　　　　　　．　　　　　_　　　　　　　_　　　　　_😭{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄😭_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．　　　　．　　　　．　　　．　　　　　　．　　　　　_　　　　　　　_　　　　　_😭{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄😭_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．　　　　．　　　　．　　　．　　　　　　．　　　　　_　　　　　　　_　　　　　_😭{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄😭_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．　　　　．　　　　．　　　．　　　　　　．　　　　　_　　　　　　　_　　　　　_😭{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄😭_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．",
        f"{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄💀_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．　　　　．　　　　．　　　．　　　　　　．　　　　　_　　　　　　　_　　　　　_💀{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄💀_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．　　　　．　　　　．　　　．　　　　　　．　　　　　_　　　　　　　_　　　　　_💀{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄💀_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．　　　　．　　　　．　　　．　　　　　　．　　　　　_　　　　　　　_　　　　　_💀{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄💀_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．　　　　．　　　　．　　　．　　　　　　．　　　　　_　　　　　　　_　　　　　_💀{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄💀_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．",
        f"{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄🤯_　　　　　　　_　　　　　_🤯{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄🤯_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．　　　　．　　　　．　　　．　　　　　　．　　　　　_　　　　　　　_　　　　　_🤯{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄🤯_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．　　　　．　　　　．　　　．　　　　　　．　　　　　_　　　　　　　_　　　　　_🤯{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄🤯_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．　　　　．　　　　．　　　．　　　　　　．　　　　　_　　　　　　　_　　　　　_🤯{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄🤯_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．",
        f"{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄🔥_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．　　　　．　　　　．　　　．　　　　　　．　　　　　_　　　　　　　_　　　　　_🔥{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄🔥_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．　　　　．　　　　．　　　．　　　　　　．　　　　　_　　　　　　　_　　　　　_🔥{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄🔥_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．　　　　．　　　　．　　　．　　　　　　．　　　　　_　　　　　　　_　　　　　_🔥{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄🔥_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　　　　　．　　　　　　　　．　　　　　　　　．　　　　　　．　　　　．　　　　．　　　．　　　　　　．　　　　　_　　　　　　　_　　　　　_🔥{target} 　𝐂𝐇𝐀𝐋　𝐁𝐇𝐀𝐆　𝐌𝐓　𝐂𝐇𝐈𝐍𝐀𝐋　𝐊𝐄　𝐁𝐀𝐂𝐇𝐄🔥_　　　　　　　_　　　　　　　_　　　　　　　　　．　　　　　        .                 .       　𝐒𝐜𝐫𝐢𝐩𝐭 𝐁𝐲 𝐀𝐫𝐞𝐬 𝐃𝐚𝐝𝐝𝐲🔥．"
    ]

    await ctx.send(f"🚀 **[{ctx.bot.user.name}] Infinite Loop Started** for **{target}** with a {delay}s delay. Type `!stop` to end.")

    while ctx.bot.is_blasting:
        for msg in messages:
            if not ctx.bot.is_blasting:
                break
            
            try:
                await ctx.send(msg)
                if delay > 0:
                    await asyncio.sleep(delay)
            except Exception as e:
                print(f"Error sending message from {ctx.bot.user.name}: {e}")
                ctx.bot.is_blasting = False
                break
    
    await ctx.send(f"🛑 [{ctx.bot.user.name}] Blast sequence stopped.")

@commands.command()
async def stop(ctx):
    # SECURITY CHECK: Only authorized IDs can stop it
    if ctx.author.id not in MY_OWNER_IDS:
        return

    if not ctx.bot.is_blasting:
        await ctx.send(f"[{ctx.bot.user.name}] Nothing is running right now.")
    else:
        ctx.bot.is_blasting = False
        await ctx.send(f"🛑 [{ctx.bot.user.name}] Turning off the blast... please wait for the current cycle to end.")

async def main():
    keep_alive() # Starts the web server in the background
    bot_instances = [MyBot(command_prefix=PREFIX, intents=intents) for _ in TOKENS]
    await asyncio.gather(*[bot.start(token) for bot, token in zip(bot_instances, TOKENS)])

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
  
