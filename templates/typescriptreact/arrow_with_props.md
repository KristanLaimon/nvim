---
name: Arrow Function with Props
description: Arrow function component with typed Props interface
index: 2
---
interface <%filename%>Props {
	children?: React.ReactNode;
	$0
}

export const <%filename%> = ({ children }: <%filename%>Props) => {
	return (
		<div>
			{children}
		</div>
	);
};
