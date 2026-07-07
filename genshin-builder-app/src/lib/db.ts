import { PrismaClient } from "@prisma/client";

/**
 * Prisma Client のシングルトン
 * Next.js の開発モードではホットリロードのたびにモジュールが再評価されるため、
 * globalThis にキャッシュして接続が増え続けるのを防ぐ。
 */
const globalForPrisma = globalThis as unknown as { prisma?: PrismaClient };

export const prisma = globalForPrisma.prisma ?? new PrismaClient();

if (process.env.NODE_ENV !== "production") {
  globalForPrisma.prisma = prisma;
}
