// 動作確認用: 保存済みの育成データを表示する一時スクリプト
import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();
const rows = await prisma.userProgress.findMany({
  select: {
    userId: true,
    characterId: true,
    level: true,
    weaponName: true,
    artifacts: true,
  },
});
console.log(JSON.stringify(rows, null, 2).slice(0, 2000));
await prisma.$disconnect();
