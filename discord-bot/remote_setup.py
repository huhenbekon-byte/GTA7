"""Разовая настройка сервера без постоянного запуска бота (только REST API, без шлюза).

  DISCORD_TOKEN=... GUILD_ID=... python remote_setup.py

Создаёт всё то же, что /настроить-сервер, и регистрирует слэш-команды.
Кнопки начнут отвечать, когда будет запущен bot.py.
"""
import asyncio
import os
import sys

import discord

import bot as B


async def main():
    B.load_env()
    token, gid = os.environ["DISCORD_TOKEN"], int(os.environ["GUILD_ID"])
    client = discord.Client(intents=discord.Intents.none(), proxy=os.environ.get("HTTPS_PROXY"))
    await client.login(token)
    try:
        guild = await client.fetch_guild(gid)

        async def refresh():
            guild._roles = {}
            for r in await guild.fetch_roles():
                guild._add_role(r)
            for c in await guild.fetch_channels():
                guild._add_channel(c)
            guild._add_member(await guild.fetch_member(client.user.id))

        await refresh()
        try:
            members = [m async for m in guild.fetch_members(limit=None)]
        except discord.HTTPException as e:
            print("Список участников недоступен:", e)
            members = []

        async def say(t):
            print(t, flush=True)

        warnings = await B.setup_guild(guild, say, refresh=refresh, members=members)
        for w in warnings:
            print("⚠️", w)

        tree = discord.app_commands.CommandTree(client)
        B.register_commands(tree)
        client._connection.application_id = client.user.id
        g = discord.Object(id=gid)
        tree.copy_global_to(guild=g)
        synced = await tree.sync(guild=g)
        print("Команд зарегистрировано:", len(synced))
    finally:
        await client.close()


if __name__ == "__main__":
    asyncio.run(main())
