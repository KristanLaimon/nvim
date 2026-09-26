---
name: Class Component
description: React class-based component with Props and State
index: 4
---
import React, { Component } from "react";

interface <%filename%>Props {
	$0
}

interface <%filename%>State {
	count: number;
}

export class <%filename%> extends Component<<%filename%>Props, <%filename%>State> {
	state: <%filename%>State = {
		count: 0,
	};

	render() {
		return (
			<div>
				<p>{this.state.count}</p>
			</div>
		);
	}
}
