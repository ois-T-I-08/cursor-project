import Image from "next/image";
import type { Character } from "@/types/character";
import { ELEMENT_INFO } from "@/lib/constants";

/**
 * キャラクターアイコン
 * APIから取得した画像URLがあれば画像を、なければ絵文字を表示する。
 */
export default function CharacterAvatar({
  character,
  size = 64,
  className = "",
}: {
  character: Character;
  size?: number;
  className?: string;
}) {
  const elementColor = ELEMENT_INFO[character.element].color;

  return (
    <div
      className={`flex shrink-0 items-center justify-center overflow-hidden rounded-full border-2 bg-[#151d2a] ${className}`}
      style={{ borderColor: elementColor, width: size, height: size }}
    >
      {character.iconUrl ? (
        <Image
          src={character.iconUrl}
          alt={character.name}
          width={size}
          height={size}
          className="size-full object-cover"
          unoptimized
        />
      ) : (
        <span style={{ fontSize: size * 0.5 }}>{character.emoji ?? "❔"}</span>
      )}
    </div>
  );
}
