---
name: Function Component with Props
description: React function component with typed Props interface
index: 0
---
interface <%filename%>Props {
	children?: React.ReactNode;
	$0
}

export function <%filename%>({ children }: <%filename%>Props) {
	return (
		<div>
			{children}
		</div>
	);
}
