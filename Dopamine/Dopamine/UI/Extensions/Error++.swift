//
//  Error++.swift
//  Fugu15
//
//  Created by sourcelocation on 17/04/2023.
//

import Foundation

extension String: LocalizedError {
    public var errorDescription: String? { return self }
}
