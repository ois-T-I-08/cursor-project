import ConsumerShell from "@/components/consumer/ConsumerShell";

export default function ConsumerLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return <ConsumerShell>{children}</ConsumerShell>;
}
